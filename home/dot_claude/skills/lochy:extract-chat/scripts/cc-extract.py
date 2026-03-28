#!/usr/bin/env python3
"""Extract human-readable conversation from a Claude Code JSONL session.

Usage:
    python3 cc-extract.py <session-id-or-path> [--leaf UUID] [--output PATH]

Arguments:
    session-id-or-path  A session UUID (searches ~/.claude/projects/) or
                        a direct path to a .jsonl file.

Options:
    --leaf UUID         Start from a specific leaf message instead of the
                        latest one. Useful when the session has branches.
    --output PATH       Write to this path instead of a temp file.
    --help              Show this message and exit.

Output:
    Writes a markdown file with YAML frontmatter (session metadata and a
    one-line summary) followed by the conversation in chronological order.
    By default, output goes to a temp file (mode 0600) in $TMPDIR and the
    path is printed to stdout.
"""

import json
import os
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path


# ---------------------------------------------------------------------------
# JSONL parsing
# ---------------------------------------------------------------------------

def load_messages(path: Path):
    """Parse a Claude Code JSONL into node/children/order structures."""
    nodes: dict[str, dict] = {}
    children: dict[str, list[str]] = {}
    ordered_uuids: list[str] = []

    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            for obj in _parse_line(line):
                uuid = obj.get("uuid")
                if uuid:
                    nodes[uuid] = obj
                    ordered_uuids.append(uuid)
                    parent = obj.get("parentUuid")
                    if parent:
                        children.setdefault(parent, []).append(uuid)

    return nodes, children, ordered_uuids


def _parse_line(line: str) -> list[dict]:
    """Parse a JSONL line, handling concatenated JSON objects."""
    try:
        return [json.loads(line)]
    except json.JSONDecodeError:
        pass
    # Concatenated objects on one line (known Claude Code quirk)
    objs = []
    depth = 0
    start = 0
    for i, ch in enumerate(line):
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                try:
                    objs.append(json.loads(line[start : i + 1]))
                except json.JSONDecodeError:
                    pass
                start = i + 1
    return objs


# ---------------------------------------------------------------------------
# Tree traversal
# ---------------------------------------------------------------------------

def find_main_leaf(nodes, children, ordered_uuids) -> str | None:
    """Find the leaf of the main (non-sidechain) conversation."""
    parents_with_children = set()
    for uid in nodes:
        for _ in children.get(uid, []):
            parents_with_children.add(uid)
            break

    for uid in reversed(ordered_uuids):
        if uid not in parents_with_children:
            obj = nodes[uid]
            if obj.get("type") in ("assistant", "user", "system", "progress"):
                return uid
    return ordered_uuids[-1] if ordered_uuids else None


def walk_chain(nodes, leaf_uuid) -> list[dict]:
    """Walk from leaf to root, return list in root→leaf order."""
    chain: list[dict] = []
    cur = leaf_uuid
    visited: set[str] = set()
    while cur and cur not in visited:
        visited.add(cur)
        if cur in nodes:
            chain.append(nodes[cur])
        cur = nodes.get(cur, {}).get("parentUuid")
    chain.reverse()
    return chain


# ---------------------------------------------------------------------------
# Text extraction & formatting
# ---------------------------------------------------------------------------

def _extract_text(content) -> str:
    """Pull readable text from message content, skipping tool noise."""
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, list):
        parts = []
        for block in content:
            if block.get("type") == "text" and block.get("text", "").strip():
                parts.append(block["text"].strip())
        return "\n".join(parts)
    return ""


def format_conversation(chain: list[dict]) -> tuple[str, dict]:
    """Return (markdown_body, metadata) from a message chain.

    metadata keys: session_id, first_ts, last_ts, user_turns, assistant_turns,
    model, branch, cwd, summary.
    """
    sections: list[str] = []
    prev_role = None
    user_turns = 0
    assistant_turns = 0
    first_user_text = ""
    model = None
    branch = None
    cwd = None

    for msg in chain:
        typ = msg.get("type")

        if not branch:
            branch = msg.get("gitBranch")
        if not cwd:
            cwd = msg.get("cwd")

        if typ == "user":
            content = msg.get("message", {}).get("content", "")
            text = _extract_text(content)
            if not text:
                continue
            user_turns += 1
            if not first_user_text:
                first_user_text = text
            if prev_role == "assistant" or prev_role is None:
                sections.append(f"\n## User\n\n{text}")
            else:
                # Consecutive user messages (tool results filtered out)
                sections.append(text)
            prev_role = "user"

        elif typ == "assistant":
            if msg.get("isApiErrorMessage"):
                continue
            if not model:
                model = msg.get("message", {}).get("model")
            content = msg.get("message", {}).get("content", [])
            text = _extract_text(content)
            if not text:
                continue
            assistant_turns += 1
            if prev_role == "assistant" and sections:
                sections[-1] += "\n" + text
            else:
                sections.append(f"\n## Assistant\n\n{text}")
            prev_role = "assistant"

    # Build a one-line summary from the first user message
    summary = first_user_text.split("\n")[0][:120] if first_user_text else ""

    timestamps = [
        msg.get("timestamp", "")
        for msg in chain
        if msg.get("timestamp")
    ]
    first_ts = timestamps[0] if timestamps else ""
    last_ts = timestamps[-1] if timestamps else ""

    meta = {
        "first_ts": first_ts,
        "last_ts": last_ts,
        "user_turns": user_turns,
        "assistant_turns": assistant_turns,
        "model": model or "unknown",
        "branch": branch or "",
        "cwd": cwd or "",
        "summary": summary,
    }

    return "\n".join(sections), meta


# ---------------------------------------------------------------------------
# Frontmatter & output
# ---------------------------------------------------------------------------

def build_output(session_id: str, body: str, meta: dict) -> str:
    """Assemble the final markdown with YAML frontmatter."""
    lines = [
        "---",
        f"source: claude-code",
        f"session: {session_id}",
        f"model: {meta['model']}",
        f"branch: {meta['branch']}",
        f"cwd: {meta['cwd']}",
        f"first_message: {meta['first_ts']}",
        f"last_message: {meta['last_ts']}",
        f"user_turns: {meta['user_turns']}",
        f"assistant_turns: {meta['assistant_turns']}",
        f"summary: {meta['summary']}",
        "---",
        "",
        f"# Chat Extract: {session_id}",
        body,
        "",
    ]
    return "\n".join(lines)


def resolve_session_path(arg: str) -> Path:
    """Resolve a session ID or file path to a .jsonl Path."""
    p = Path(arg)
    if p.exists() and p.suffix == ".jsonl":
        return p

    # Search ~/.claude/projects/ for a matching session ID
    projects = Path.home() / ".claude" / "projects"
    if projects.is_dir():
        for d in projects.iterdir():
            if not d.is_dir():
                continue
            candidate = d / f"{arg}.jsonl"
            if candidate.exists():
                return candidate

    print(f"Error: Could not find session: {arg}", file=sys.stderr)
    print(f"Provide a session UUID or a direct path to a .jsonl file.", file=sys.stderr)
    sys.exit(1)


def write_output(content: str, output_path: str | None, session_id: str) -> str:
    """Write content to output_path or a secure temp file. Returns the path."""
    if output_path:
        p = Path(output_path)
        p.write_text(content)
        os.chmod(p, 0o600)
        return str(p)

    tmpdir = Path(tempfile.gettempdir())
    slug = session_id[:8] if len(session_id) > 8 else session_id
    ts = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    out = tmpdir / f"chat-extract-{slug}-{ts}.md"
    out.write_text(content)
    os.chmod(out, 0o600)
    return str(out)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    args = sys.argv[1:]

    if not args or "--help" in args or "-h" in args:
        print(__doc__.strip())
        sys.exit(0)

    positional = []
    leaf_uuid = None
    output_path = None
    i = 0
    while i < len(args):
        if args[i] == "--leaf" and i + 1 < len(args):
            leaf_uuid = args[i + 1]
            i += 2
        elif args[i] == "--output" and i + 1 < len(args):
            output_path = args[i + 1]
            i += 2
        else:
            positional.append(args[i])
            i += 1

    if not positional:
        print("Error: session-id-or-path is required.", file=sys.stderr)
        sys.exit(1)

    path = resolve_session_path(positional[0])
    session_id = path.stem

    nodes, children, ordered_uuids = load_messages(path)

    if not ordered_uuids:
        print("Error: No messages found in session.", file=sys.stderr)
        sys.exit(1)

    if not leaf_uuid:
        leaf_uuid = find_main_leaf(nodes, children, ordered_uuids)

    chain = walk_chain(nodes, leaf_uuid)
    body, meta = format_conversation(chain)
    content = build_output(session_id, body, meta)

    out_path = write_output(content, output_path, session_id)
    print(out_path)


if __name__ == "__main__":
    main()
