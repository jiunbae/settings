#!/usr/bin/env python3
"""
Codex Context Push - OpenAI Codex CLI 세션을 Obsidian CouchDB로 푸시

~/.codex/history.jsonl 에서 세션 데이터를 마크다운으로 변환하여 CouchDB에 업로드합니다.

사용법:
    python codex-context-push.py                # 변경된 파일만 푸시
    python codex-context-push.py --dry-run      # 미리보기
    python codex-context-push.py --force        # 전부 강제 푸시
    python codex-context-push.py -v             # 상세 출력
"""

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor

from couchdb_client import create_client, WORKSPACE_VARIANTS

# ============================================================================
# Configuration
# ============================================================================

CODEX_DIR = Path.home() / ".codex"
HISTORY_FILE = CODEX_DIR / "history.jsonl"
CONTEXT_PREFIX = "codex-context"
STATE_FILE = Path(__file__).resolve().parent / ".codex-push-state.json"


# ============================================================================
# Session Discovery
# ============================================================================

def load_codex_sessions() -> dict[str, dict]:
    """history.jsonl에서 세션 데이터를 스트리밍으로 로드"""
    sessions = {}
    if not HISTORY_FILE.exists():
        return sessions

    with open(HISTORY_FILE, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue

            sid = entry.get("session_id", "")
            if not sid:
                continue

            if sid not in sessions:
                sessions[sid] = {
                    "id": sid,
                    "ts": entry.get("ts", 0),
                    "prompts": [],
                    "last_ts": entry.get("ts", 0),
                }

            sessions[sid]["prompts"].append(entry.get("text", ""))
            ts = entry.get("ts", 0)
            if ts > sessions[sid]["last_ts"]:
                sessions[sid]["last_ts"] = ts
            if ts < sessions[sid]["ts"]:
                sessions[sid]["ts"] = ts

    return sessions


def load_push_state() -> dict[str, int]:
    """이전 푸시 상태 로드 (session_id → last_ts)"""
    if not STATE_FILE.exists():
        return {}
    try:
        return json.loads(STATE_FILE.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return {}


def save_push_state(sessions: dict[str, dict]) -> None:
    """푸시 상태 저장"""
    state = {sid: s["last_ts"] for sid, s in sessions.items()}
    STATE_FILE.write_text(json.dumps(state), encoding="utf-8")


# ============================================================================
# Markdown Generation
# ============================================================================

def _ts_to_date(ts: int) -> str:
    try:
        return datetime.fromtimestamp(ts, tz=timezone.utc).strftime("%Y-%m-%d")
    except (ValueError, OSError):
        return "unknown"


def _ts_to_datetime(ts: int) -> str:
    try:
        return datetime.fromtimestamp(ts, tz=timezone.utc).strftime("%Y-%m-%d %H:%M")
    except (ValueError, OSError):
        return "unknown"


def _compute_duration(start_ts: int, end_ts: int) -> str:
    total_mins = max(0, (end_ts - start_ts)) // 60
    if total_mins < 60:
        return f"{total_mins}m"
    hours = total_mins // 60
    mins = total_mins % 60
    return f"{hours}h {mins}m"


def _sanitize_table_cell(text: str) -> str:
    return text.replace("|", "\\|").replace("\n", " ")


def generate_session_md(session: dict) -> str:
    prompts = session["prompts"]
    first_prompt = prompts[0] if prompts else ""
    summary = _sanitize_table_cell(first_prompt[:80]) if first_prompt else "Untitled session"
    duration = _compute_duration(session["ts"], session["last_ts"])

    lines = [
        "---",
        f"sessionId: {session['id']}",
        "tool: codex",
        f"created: {_ts_to_datetime(session['ts'])}",
        f"modified: {_ts_to_datetime(session['last_ts'])}",
        f"messageCount: {len(prompts)}",
        "tags: [codex-session, auto-generated]",
        "---",
        "",
        f"# {summary}",
        "",
    ]

    if first_prompt:
        preview = first_prompt[:500].replace("\n", "\n> ")
        if len(first_prompt) > 500:
            preview += "..."
        lines.extend([f"> {preview}", ""])

    lines.extend([
        f"- **Messages**: {len(prompts)}",
        f"- **Duration**: ~{duration}",
        "",
    ])

    if len(prompts) > 1:
        lines.extend(["## Prompts", ""])
        for i, p in enumerate(prompts[:10]):
            preview = p[:120].replace("\n", " ")
            if len(p) > 120:
                preview += "..."
            lines.append(f"{i+1}. {preview}")
        if len(prompts) > 10:
            lines.append(f"\n... and {len(prompts) - 10} more")
        lines.append("")

    return "\n".join(lines)


def generate_index_md(sessions: list[dict]) -> str:
    now = datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
    lines = [
        "---",
        "tool: codex",
        f"updated: {now}",
        "tags: [codex-context, index, auto-generated]",
        "---",
        "",
        "# Codex Sessions",
        "",
        f"## Sessions ({len(sessions)})",
        "",
        "| Date | Summary | Messages | Duration |",
        "|------|---------|----------|----------|",
    ]

    for s in sorted(sessions, key=lambda x: x["last_ts"], reverse=True):
        date = _ts_to_date(s["ts"])
        summary = _sanitize_table_cell(
            s["prompts"][0][:50] if s["prompts"] else "Untitled"
        )
        msgs = len(s["prompts"])
        duration = _compute_duration(s["ts"], s["last_ts"])
        lines.append(f"| {date} | {summary} | {msgs} | {duration} |")

    lines.append("")
    return "\n".join(lines)


# ============================================================================
# Main Push Logic
# ============================================================================

def push_all(force=False, dry_run=False, verbose=False):
    stats = {"created": 0, "updated": 0, "skipped": 0, "errors": 0}

    print(f"\n[Discover] Loading Codex sessions...")
    sessions = load_codex_sessions()
    print(f"  Found {len(sessions)} sessions")

    if not sessions:
        print("  No sessions to push.")
        return stats

    # Change detection
    prev_state = {} if force else load_push_state()
    changed = {}
    for sid, s in sessions.items():
        if sid not in prev_state or prev_state[sid] != s["last_ts"]:
            changed[sid] = s
        else:
            stats["skipped"] += 1

    if not changed and not force:
        print(f"  No changes detected ({stats['skipped']} skipped)")
        return stats

    print(f"  Changed: {len(changed)}, Skipped: {stats['skipped']}")

    client = create_client(user_agent="codex-context-push/1.0")
    now_ms = int(datetime.now().timestamp() * 1000)

    # Shared thread pool for all uploads
    with ThreadPoolExecutor(max_workers=10) as executor:
        # Push index (always when there are changes)
        all_sessions = sorted(sessions.values(), key=lambda x: x["last_ts"], reverse=True)
        index_content = generate_index_md(all_sessions)
        index_path = f"{CONTEXT_PREFIX}/INDEX.md"
        print(f"\n[Push] Index ({len(all_sessions)} sessions)")
        result = client.push_content(
            index_path, index_content, now_ms,
            executor=executor, dry_run=dry_run, verbose=verbose,
        )
        stats[result if result in stats else "errors"] += 1

        # Push changed session files
        print(f"[Push] Session files ({len(changed)} changed)...")
        for sid, session in changed.items():
            date_str = _ts_to_date(session["ts"])
            short_id = sid[:8]
            session_path = f"{CONTEXT_PREFIX}/sessions/{date_str}-{short_id}.md"
            mtime_ms = session["last_ts"] * 1000

            content = generate_session_md(session)
            result = client.push_content(
                session_path, content, mtime_ms,
                executor=executor, dry_run=dry_run, verbose=verbose,
            )
            stats[result if result in stats else "errors"] += 1

    # Save state after successful push
    if not dry_run and stats["errors"] == 0:
        save_push_state(sessions)

    return stats


def main():
    parser = argparse.ArgumentParser(
        description="Push Codex CLI session context to Obsidian CouchDB"
    )
    parser.add_argument("--dry-run", action="store_true", help="Preview without uploading")
    parser.add_argument("--force", action="store_true", help="Push all files regardless")
    parser.add_argument("-v", "--verbose", action="store_true", help="Verbose output")

    args = parser.parse_args()

    print("=" * 60)
    print("Codex Context Push → Obsidian CouchDB")
    print("=" * 60)

    if args.dry_run:
        print("[DRY RUN] No changes will be made")

    try:
        stats = push_all(force=args.force, dry_run=args.dry_run, verbose=args.verbose)
        print()
        print("=" * 60)
        print("Summary:")
        print(f"  Created:  {stats['created']}")
        print(f"  Updated:  {stats['updated']}")
        print(f"  Skipped:  {stats['skipped']}")
        print(f"  Errors:   {stats['errors']}")
        print("=" * 60)
    except KeyboardInterrupt:
        print("\n\nInterrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\nError: {e}")
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
