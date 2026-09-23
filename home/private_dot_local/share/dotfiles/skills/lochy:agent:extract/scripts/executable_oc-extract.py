#!/usr/bin/env python3
"""Extract human-readable conversation from an opencode session.

Uses opencode's OFFICIAL export path (`opencode export <id>`) rather than
reading the SQLite DB directly — the DB schema is an internal Drizzle detail
that drifts between versions, whereas `export` is a documented, stable command.

Usage:
    python3 oc-extract.py <session-id> [--sanitize] [--text-only] [--output PATH]
    python3 oc-extract.py --file <export.json> [--text-only] [--output PATH]

Arguments:
    session-id          An opencode session id (e.g. ses_0fe328e5cffe...).
                        Exported via `opencode export <id>`.

Options:
    --sanitize          Pass through to `opencode export --sanitize` to redact
                        sensitive transcript and file data.
    --file PATH         Render an already-exported JSON file instead of calling
                        `opencode export` (offline / pre-captured exports).
    --text-only         Reading-transcript mode: user/assistant text only, tool
                        calls collapsed to a one-line marker (mirrors cc-extract).
                        Default is FULL: tool calls with inputs + outputs.
    --output PATH       Write to this path instead of a temp file.
    --help              Show this message and exit.

Output:
    Writes a markdown file with YAML frontmatter (session metadata + a one-line
    summary) followed by the conversation in chronological order. By default,
    output goes to a temp file (mode 0600) in $TMPDIR and the path is printed
    to stdout.

Why not read the SQLite DB directly:
    `~/.local/share/opencode/opencode.db` (tables session/message/part) is an
    internal, migration-versioned store. `opencode export` is the paved path;
    `opencode db <query>` exists only as a documented escape hatch.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path


# ---------------------------------------------------------------------------
# Acquire the export JSON (paved path: `opencode export`)
# ---------------------------------------------------------------------------

def _strip_leading_noise(raw: bytes) -> bytes:
    """opencode plugins may prepend a terminal-title OSC escape
    (\\033]0;<cwd>: ready\\007) before the JSON. Drop everything before the
    first top-level '{'. (`--pure` also avoids it, but stripping is robust
    even when plugins are active and stdout is piped.)"""
    brace = raw.find(b"{")
    if brace == -1:
        return raw
    return raw[brace:]


def export_session_to_file(session_id: str, sanitize: bool, dest: str) -> None:
    """Run `opencode export <id>`, writing the JSON to `dest`.

    IMPORTANT: stdout is redirected to a real file handle, NOT captured via a
    pipe. `opencode export` truncates at a 64KB pipe buffer when stdout is a
    pipe (subprocess capture_output), but writes the full payload to a file.
    """
    cmd = ["opencode", "export", session_id, "--pure"]
    if sanitize:
        cmd.append("--sanitize")
    try:
        with open(dest, "wb") as fh:
            proc = subprocess.run(cmd, stdout=fh, stderr=subprocess.PIPE)
    except FileNotFoundError:
        print(
            "Error: `opencode` not found on PATH. Install opencode, or pass an "
            "already-exported file with --file.",
            file=sys.stderr,
        )
        sys.exit(1)
    if proc.returncode != 0:
        err = proc.stderr.decode("utf-8", "replace").strip()
        print(f"Error: `opencode export {session_id}` failed: {err}", file=sys.stderr)
        sys.exit(1)


def export_session(session_id: str, sanitize: bool) -> dict:
    """Export a session via the paved `opencode export` path and parse it."""
    fd, tmp = tempfile.mkstemp(suffix=".json")
    os.close(fd)
    try:
        export_session_to_file(session_id, sanitize, tmp)
        raw = Path(tmp).read_bytes()
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass
    return _parse_export(raw, source=f"opencode export {session_id}")


def load_export_file(path: str) -> dict:
    raw = Path(path).read_bytes()
    return _parse_export(raw, source=path)


def _parse_export(raw: bytes, source: str) -> dict:
    try:
        return json.loads(_strip_leading_noise(raw))
    except json.JSONDecodeError as e:
        print(f"Error: could not parse export JSON from {source}: {e}", file=sys.stderr)
        sys.exit(1)


# ---------------------------------------------------------------------------
# Part rendering
# ---------------------------------------------------------------------------

def _fence(text: str, lang: str = "") -> str:
    """Wrap text in a code fence longer than any backtick run inside it."""
    longest = run = 0
    for ch in text:
        if ch == "`":
            run += 1
            longest = max(longest, run)
        else:
            run = 0
    bar = "`" * max(3, longest + 1)
    return f"{bar}{lang}\n{text}\n{bar}"


def _render_tool(d: dict, text_only: bool) -> str:
    tool = d.get("tool", "?")
    state = d.get("state") or {}
    status = state.get("status", "?")
    if text_only:
        return f"_🔧 {tool} ({status})_"
    out = [f"**🔧 tool: `{tool}`** ({status})"]
    inp = state.get("input")
    if inp is not None:
        if isinstance(inp, dict) and len(inp) == 1 and isinstance(next(iter(inp.values())), str):
            k, v = next(iter(inp.items()))
            out.append(f"_input ({k}):_\n" + _fence(v))
        else:
            out.append("_input:_\n" + _fence(json.dumps(inp, indent=2)))
    output = state.get("output")
    if output:
        out.append("_output:_\n" + _fence(output if isinstance(output, str) else json.dumps(output, indent=2)))
    err = state.get("error")
    if err:
        out.append("_error:_\n" + _fence(err if isinstance(err, str) else json.dumps(err, indent=2)))
    return "\n\n".join(out)


def _render_part(d: dict, text_only: bool) -> str | None:
    t = d.get("type")
    if t == "text":
        return (d.get("text") or "").strip() or None
    if t == "tool":
        return _render_tool(d, text_only)
    if t == "file":
        if text_only:
            return None
        return f"_📎 attached file: `{d.get('filename', d.get('url', '?'))}`_"
    if t == "patch":
        if text_only:
            return None
        files = d.get("files") or []
        if isinstance(files, str):
            files = [files]
        listing = "\n".join(f"- `{f}`" for f in files)
        return f"_📝 patch `{str(d.get('hash', ''))[:12]}` →_\n{listing}"
    if t == "compaction":
        return (
            "\n---\n\n> ⚠️ **context compaction** "
            f"(auto={d.get('auto')}) — history before this point was summarised; "
            f"tail resumes at `{d.get('tail_start_id', '')}`.\n\n---"
        )
    # step-start / step-finish are token accounting — skip.
    return None


# ---------------------------------------------------------------------------
# Conversation formatting
# ---------------------------------------------------------------------------

def _ts(ms) -> str:
    if not ms:
        return ""
    try:
        return datetime.fromtimestamp(int(ms) / 1000, tz=timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    except (ValueError, TypeError, OSError):
        return ""


def _msg_created(info: dict):
    t = info.get("time") or {}
    return t.get("created") if isinstance(t, dict) else None


def format_conversation(export: dict, text_only: bool) -> tuple[str, dict]:
    info = export.get("info", {})
    messages = export.get("messages", [])

    sections: list[str] = []
    user_turns = assistant_turns = 0
    first_user_text = ""
    first_ts = last_ts = ""

    for m in messages:
        minfo = m.get("info", {})
        role = minfo.get("role", "?")
        created = _ts(_msg_created(minfo))
        if created:
            first_ts = first_ts or created
            last_ts = created

        if role == "user":
            user_turns += 1
            header = "## 🧑 User"
            meta_line = created
        elif role == "assistant":
            assistant_turns += 1
            agent = minfo.get("agent", "")
            header = "## 🤖 Assistant"
            meta_line = f"{agent} · {created}" if agent else created
        else:
            header = f"## {role}"
            meta_line = created

        chunks: list[str] = []
        for p in m.get("parts", []):
            rendered = _render_part(p, text_only)
            if rendered:
                chunks.append(rendered)
                if role == "user" and not first_user_text and p.get("type") == "text":
                    first_user_text = (p.get("text") or "").strip()

        if text_only and not any(c for c in chunks):
            # In text-only mode a message with only tool noise has nothing to show.
            continue

        block = [header, f"<sub>{meta_line}</sub>", ""]
        block.append("\n\n".join(chunks) if chunks else "_(no renderable content)_")
        block.append("")
        block.append("---")
        sections.append("\n".join(block))

    model = info.get("model")
    if isinstance(model, dict):
        model = model.get("id", "")

    meta = {
        "title": info.get("title", ""),
        "agent": info.get("agent", ""),
        "model": model or "unknown",
        "directory": info.get("directory", ""),
        "first_ts": first_ts,
        "last_ts": last_ts,
        "user_turns": user_turns,
        "assistant_turns": assistant_turns,
        "summary": first_user_text.split("\n")[0][:120] if first_user_text else "",
    }
    return "\n\n".join(sections), meta


def build_output(session_id: str, body: str, meta: dict, text_only: bool) -> str:
    lines = [
        "---",
        "source: opencode",
        f"session: {session_id}",
        f'title: "{meta["title"]}"',
        f'agent: "{meta["agent"]}"',
        f"model: {meta['model']}",
        f"directory: {meta['directory']}",
        f"first_message: {meta['first_ts']}",
        f"last_message: {meta['last_ts']}",
        f"user_turns: {meta['user_turns']}",
        f"assistant_turns: {meta['assistant_turns']}",
        f"mode: {'text-only' if text_only else 'full'}",
        f"summary: {meta['summary']}",
        "---",
        "",
        f'# {meta["title"] or session_id}',
        "",
        f"> opencode session `{session_id}` — agent **{meta['agent']}**, model `{meta['model']}`.",
        "",
        body,
        "",
    ]
    return "\n".join(lines)


def write_output(content: str, output_path: str | None, session_id: str) -> str:
    if output_path:
        p = Path(output_path)
        p.write_text(content)
        os.chmod(p, 0o600)
        return str(p)
    tmpdir = Path(tempfile.gettempdir())
    slug = session_id[:12] if len(session_id) > 12 else session_id
    ts = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    out = tmpdir / f"chat-extract-{slug}-{ts}.md"
    out.write_text(content)
    os.chmod(out, 0o600)
    return str(out)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    args = sys.argv[1:]
    if not args or "--help" in args or "-h" in args:
        print(__doc__.strip())
        sys.exit(0)

    positional: list[str] = []
    sanitize = text_only = False
    output_path = file_path = None
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--sanitize":
            sanitize = True
            i += 1
        elif a == "--text-only":
            text_only = True
            i += 1
        elif a == "--file" and i + 1 < len(args):
            file_path = args[i + 1]
            i += 2
        elif a == "--output" and i + 1 < len(args):
            output_path = args[i + 1]
            i += 2
        else:
            positional.append(a)
            i += 1

    if file_path:
        export = load_export_file(file_path)
        session_id = export.get("info", {}).get("id", Path(file_path).stem)
    else:
        if not positional:
            print("Error: session-id is required (or use --file PATH).", file=sys.stderr)
            sys.exit(1)
        session_id = positional[0]
        export = export_session(session_id, sanitize)

    if not export.get("messages"):
        print("Error: no messages found in export.", file=sys.stderr)
        sys.exit(1)

    body, meta = format_conversation(export, text_only)
    content = build_output(session_id, body, meta, text_only)
    print(write_output(content, output_path, session_id))


if __name__ == "__main__":
    main()
