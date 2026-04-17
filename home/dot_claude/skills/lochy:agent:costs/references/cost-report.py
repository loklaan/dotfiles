#!/usr/bin/env python3
"""Claude Code session cost report from local JSONL logs."""

import json
import os
import glob
from collections import defaultdict
from datetime import datetime, timedelta, timezone

# ── Pricing per 1M tokens (USD) ──────────────────────────────────────────────

PRICING = {
    "claude-sonnet-4-6": {"input": 3.0, "output": 15.0, "cache_write": 3.75, "cache_read": 0.30},
    "claude-sonnet-4-5-20250514": {"input": 3.0, "output": 15.0, "cache_write": 3.75, "cache_read": 0.30},
    "claude-opus-4-7": {"input": 15.0, "output": 75.0, "cache_write": 18.75, "cache_read": 1.50},
    "claude-opus-4-6": {"input": 15.0, "output": 75.0, "cache_write": 18.75, "cache_read": 1.50},
    "claude-opus-4-5-20250414": {"input": 15.0, "output": 75.0, "cache_write": 18.75, "cache_read": 1.50},
    "claude-haiku-4-5-20251001": {"input": 0.80, "output": 4.0, "cache_write": 1.0, "cache_read": 0.08},
}
DEFAULT_PRICING = {"input": 3.0, "output": 15.0, "cache_write": 3.75, "cache_read": 0.30}

# ── Paths ─────────────────────────────────────────────────────────────────────

HOME = os.path.expanduser("~")
PROJECTS_DIR = os.path.join(HOME, ".claude", "projects")
SESSIONS_DIR = os.path.join(HOME, ".claude", "sessions")


def cost_for_usage(usage, model):
    prices = PRICING.get(model, DEFAULT_PRICING)
    inp = usage.get("input_tokens", 0)
    out = usage.get("output_tokens", 0)
    cw = usage.get("cache_creation_input_tokens", 0)
    cr = usage.get("cache_read_input_tokens", 0)
    return (inp * prices["input"] + out * prices["output"] +
            cw * prices["cache_write"] + cr * prices["cache_read"]) / 1_000_000


def parse_timestamp(ts):
    """Parse ISO timestamp or epoch ms to date."""
    if isinstance(ts, (int, float)):
        return datetime.fromtimestamp(ts / 1000, tz=timezone.utc).date()
    if isinstance(ts, str):
        # strip trailing Z, handle fractional seconds
        ts = ts.replace("Z", "+00:00")
        try:
            return datetime.fromisoformat(ts).date()
        except ValueError:
            return None
    return None


def shorten(path):
    return path.replace(HOME, "~")


def main():
    # ── Collect usage from all JSONL files ────────────────────────────────

    jsonl_files = glob.glob(os.path.join(PROJECTS_DIR, "*", "*.jsonl"))
    jsonl_files += glob.glob(os.path.join(PROJECTS_DIR, "*", "*", "subagents", "*.jsonl"))

    dir_costs = defaultdict(lambda: {"cost": 0.0, "input": 0, "output": 0, "sessions": set()})
    daily_costs = defaultdict(float)
    all_dates = []
    oldest_ts = None
    newest_ts = None

    for jf in jsonl_files:
        parts = jf.replace(PROJECTS_DIR + "/", "").split("/")
        proj_dir_name = parts[0]
        default_cwd = "/" + proj_dir_name.lstrip("-").replace("-", "/")

        try:
            with open(jf) as f:
                for line in f:
                    try:
                        obj = json.loads(line)
                    except (json.JSONDecodeError, ValueError):
                        continue

                    line_cwd = obj.get("cwd", default_cwd)
                    sid = obj.get("sessionId", "")
                    timestamp = obj.get("timestamp")
                    date = parse_timestamp(timestamp)

                    # Track session age range
                    if date:
                        all_dates.append(date)
                        if oldest_ts is None or date < oldest_ts:
                            oldest_ts = date
                        if newest_ts is None or date > newest_ts:
                            newest_ts = date

                    data = obj.get("data", {})
                    if not isinstance(data, dict):
                        continue
                    msg = data.get("message", {})
                    if not isinstance(msg, dict):
                        continue
                    inner = msg.get("message", {})
                    if not isinstance(inner, dict):
                        continue
                    usage = inner.get("usage")
                    if not usage:
                        continue

                    model = inner.get("model", "unknown")
                    cost = cost_for_usage(usage, model)

                    entry = dir_costs[line_cwd]
                    entry["cost"] += cost
                    entry["input"] += usage.get("input_tokens", 0)
                    entry["output"] += usage.get("output_tokens", 0)
                    entry["sessions"].add(sid)

                    if date:
                        daily_costs[date] += cost
        except (OSError, IOError):
            continue

    if not dir_costs:
        print("No session data found in ~/.claude/projects/")
        return

    total_cost = sum(v["cost"] for v in dir_costs.values())

    # ── Session age range ─────────────────────────────────────────────────

    print("SESSION RANGE")
    print("─" * 60)
    if oldest_ts and newest_ts:
        span = (newest_ts - oldest_ts).days
        print(f"  Oldest : {oldest_ts}  ({span}d ago)")
        print(f"  Newest : {newest_ts}")
        print(f"  Sessions on disk : ~{sum(len(v['sessions']) for v in dir_costs.values())}")
    print()

    # ── Cost by directory ─────────────────────────────────────────────────

    sorted_dirs = sorted(dir_costs.items(), key=lambda x: -x[1]["cost"])

    print("COST BY DIRECTORY")
    print("─" * 90)
    print(f"  {'Directory':<55} {'Sess':>5} {'In':>8} {'Out':>8} {'Cost':>9}")
    print(f"  {'':─<55} {'':─>5} {'':─>8} {'':─>8} {'':─>9}")
    for d, v in sorted_dirs:
        short = shorten(d)
        if len(short) > 55:
            short = "…" + short[-(54):]
        sessions = len(v["sessions"])
        inp_k = f"{v['input']/1000:.0f}k"
        out_k = f"{v['output']/1000:.0f}k"
        print(f"  {short:<55} {sessions:>5} {inp_k:>8} {out_k:>8} ${v['cost']:>8.2f}")
    print(f"  {'':─<55} {'':─>5} {'':─>8} {'':─>8} {'':─>9}")
    print(f"  {'TOTAL':<55} {'':>5} {'':>8} {'':>8} ${total_cost:>8.2f}")
    print()

    # ── Daily breakdown (past 7 days) ─────────────────────────────────────

    today = datetime.now(timezone.utc).date()
    print("DAILY COSTS (past 7 days)")
    print("─" * 40)
    for i in range(6, -1, -1):
        day = today - timedelta(days=i)
        cost = daily_costs.get(day, 0.0)
        bar = "█" * int(cost / max(max(daily_costs.values(), default=1), 0.01) * 30) if cost > 0 else ""
        label = "today" if i == 0 else day.strftime("%a")
        print(f"  {day}  {label:<5}  ${cost:>8.2f}  {bar}")
    week_total = sum(daily_costs.get(today - timedelta(days=i), 0.0) for i in range(7))
    print(f"  {'':─<40}")
    print(f"  {'7-day total':<24} ${week_total:>8.2f}")
    print()

    # ── Weekly breakdown (all time) ───────────────────────────────────────

    if oldest_ts:
        weekly_costs = defaultdict(float)
        for date, cost in daily_costs.items():
            # Week starting Monday
            week_start = date - timedelta(days=date.weekday())
            weekly_costs[week_start] += cost

        sorted_weeks = sorted(weekly_costs.items())
        print("WEEKLY COSTS (all sessions on disk)")
        print("─" * 45)
        max_week = max(weekly_costs.values(), default=1)
        for week_start, cost in sorted_weeks:
            week_end = week_start + timedelta(days=6)
            bar = "█" * int(cost / max(max_week, 0.01) * 30) if cost > 0 else ""
            print(f"  {week_start} → {week_end}  ${cost:>8.2f}  {bar}")
        print(f"  {'':─<45}")
        print(f"  {'All-time total':<29} ${total_cost:>8.2f}")
        print()


if __name__ == "__main__":
    main()
