#!/usr/bin/env python3
"""
OpenCode Context Push - OpenCode 세션을 Obsidian CouchDB로 푸시

~/.local/share/opencode/opencode.db (SQLite)에서 세션 데이터를 마크다운으로
변환하여 CouchDB에 업로드합니다.

사용법:
    python opencode-context-push.py                # 변경된 파일만 푸시
    python opencode-context-push.py --dry-run      # 미리보기
    python opencode-context-push.py --force        # 전부 강제 푸시
    python opencode-context-push.py --project NAME # 특정 프로젝트만
    python opencode-context-push.py -v             # 상세 출력
"""

import argparse
import json
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional
from concurrent.futures import ThreadPoolExecutor

from couchdb_client import create_client, WORKSPACE_VARIANTS

# ============================================================================
# Configuration
# ============================================================================

OPENCODE_DB = Path.home() / ".local" / "share" / "opencode" / "opencode.db"
CONTEXT_PREFIX = "opencode-context"
STATE_FILE = Path(__file__).resolve().parent / ".opencode-push-state.json"


# ============================================================================
# Session Discovery from SQLite
# ============================================================================

def resolve_vault_path(directory: str) -> Optional[str]:
    """프로젝트 디렉토리 → vault 상대 경로"""
    home = str(Path.home())
    if not directory or not directory.startswith(home):
        return None
    # Resolve to prevent path traversal
    resolved = str(Path(directory).resolve())
    if not resolved.startswith(home + "/"):
        return None
    rel = resolved[len(home) + 1:]
    for variant in WORKSPACE_VARIANTS:
        if rel.startswith(variant + "/") or rel == variant:
            return rel
    return None


def load_projects_and_sessions(project_filter: Optional[str] = None) -> list[dict]:
    """OpenCode DB에서 프로젝트와 세션 로드"""
    with sqlite3.connect(str(OPENCODE_DB), timeout=10) as db:
        db.row_factory = sqlite3.Row
        cursor = db.cursor()

        # 프로젝트 로드
        cursor.execute("SELECT id, worktree, name FROM project")
        projects = {}
        for row in cursor.fetchall():
            vault_path = resolve_vault_path(row["worktree"])
            if not vault_path:
                continue
            if project_filter and project_filter not in vault_path:
                continue
            projects[row["id"]] = {
                "id": row["id"],
                "worktree": row["worktree"],
                "vault_path": vault_path,
                "name": row["name"] or vault_path.split("/")[-1],
                "sessions": [],
            }

        if not projects:
            return []

        # 세션 로드
        placeholders = ",".join("?" for _ in projects)
        cursor.execute(f"""
            SELECT id, project_id, title, slug, directory,
                   summary_additions, summary_deletions, summary_files,
                   time_created, time_updated
            FROM session
            WHERE project_id IN ({placeholders})
            ORDER BY time_updated DESC
        """, list(projects.keys()))

        session_ids = []
        sessions_map = {}
        for row in cursor.fetchall():
            pid = row["project_id"]
            if pid not in projects:
                continue
            session = {
                "id": row["id"],
                "title": row["title"] or "Untitled",
                "slug": row["slug"] or "",
                "directory": row["directory"] or "",
                "additions": row["summary_additions"] or 0,
                "deletions": row["summary_deletions"] or 0,
                "files": row["summary_files"] or 0,
                "created": row["time_created"],
                "updated": row["time_updated"],
                "first_prompt": "",
                "message_count": 0,
            }
            projects[pid]["sessions"].append(session)
            session_ids.append(row["id"])
            sessions_map[row["id"]] = session

        # Batch: 메시지 수 조회
        if session_ids:
            cursor.execute(f"""
                SELECT session_id, COUNT(*) as cnt
                FROM message
                WHERE session_id IN ({",".join("?" for _ in session_ids)})
                GROUP BY session_id
            """, session_ids)
            for row in cursor.fetchall():
                if row["session_id"] in sessions_map:
                    sessions_map[row["session_id"]]["message_count"] = row["cnt"]

            # Batch: 첫 텍스트 프롬프트 조회
            cursor.execute(f"""
                SELECT m.session_id, p.data
                FROM part p
                JOIN message m ON p.message_id = m.id
                WHERE m.session_id IN ({",".join("?" for _ in session_ids)})
                ORDER BY p.time_created ASC
            """, session_ids)

            seen_sessions = set()
            for row in cursor.fetchall():
                sid = row["session_id"]
                if sid in seen_sessions:
                    continue
                try:
                    pdata = json.loads(row["data"])
                    if pdata.get("type") == "text" and pdata.get("text"):
                        sessions_map[sid]["first_prompt"] = pdata["text"]
                        seen_sessions.add(sid)
                except (json.JSONDecodeError, KeyError):
                    pass

    return [p for p in projects.values() if p["sessions"]]


def load_push_state() -> dict[str, int]:
    """이전 푸시 상태 로드 (session_id → updated_ts)"""
    if not STATE_FILE.exists():
        return {}
    try:
        return json.loads(STATE_FILE.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return {}


def save_push_state(projects: list[dict]) -> None:
    """푸시 상태 저장"""
    state = {}
    for p in projects:
        for s in p["sessions"]:
            state[s["id"]] = s["updated"]
    STATE_FILE.write_text(json.dumps(state), encoding="utf-8")


# ============================================================================
# Markdown Generation
# ============================================================================

def _ms_to_date(ms: int) -> str:
    try:
        return datetime.fromtimestamp(ms / 1000, tz=timezone.utc).strftime("%Y-%m-%d")
    except (ValueError, OSError):
        return "unknown"


def _ms_to_datetime(ms: int) -> str:
    try:
        return datetime.fromtimestamp(ms / 1000, tz=timezone.utc).strftime("%Y-%m-%d %H:%M")
    except (ValueError, OSError):
        return "unknown"


def _compute_duration(start_ms: int, end_ms: int) -> str:
    total_mins = max(0, (end_ms - start_ms)) // 60000
    if total_mins < 60:
        return f"{total_mins}m"
    hours = total_mins // 60
    mins = total_mins % 60
    return f"{hours}h {mins}m"


def _sanitize_table_cell(text: str) -> str:
    return text.replace("|", "\\|").replace("\n", " ")


def generate_session_md(session: dict, project_name: str) -> str:
    title = _sanitize_table_cell(session["title"])
    duration = _compute_duration(session["created"], session["updated"])

    lines = [
        "---",
        f"sessionId: {session['id']}",
        "tool: opencode",
        f"project: {project_name}",
        f"created: {_ms_to_datetime(session['created'])}",
        f"modified: {_ms_to_datetime(session['updated'])}",
        f"messageCount: {session['message_count']}",
    ]
    if session["slug"]:
        lines.append(f"slug: {session['slug']}")
    lines.extend([
        "tags: [opencode-session, auto-generated]",
        "---",
        "",
        f"# {title}",
        "",
    ])

    if session["first_prompt"]:
        preview = session["first_prompt"][:500].replace("\n", "\n> ")
        if len(session["first_prompt"]) > 500:
            preview += "..."
        lines.extend([f"> {preview}", ""])

    lines.extend([
        f"- **Messages**: {session['message_count']}",
        f"- **Duration**: ~{duration}",
    ])
    if session["additions"] or session["deletions"]:
        lines.append(f"- **Changes**: +{session['additions']}/-{session['deletions']} ({session['files']} files)")
    lines.append("")

    return "\n".join(lines)


def generate_project_index(project: dict) -> str:
    vault_path = project["vault_path"]
    sessions = project["sessions"]
    now = datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
    project_name = project["name"]

    lines = [
        "---",
        f"project: {project_name}",
        "tool: opencode",
        f"updated: {now}",
        "tags: [opencode-context, index, auto-generated]",
        "---",
        "",
        f"# OpenCode Context: {project_name}",
        "",
        f"## Sessions ({len(sessions)})",
        "",
        "| Date | Title | Messages | Changes | Duration |",
        "|------|-------|----------|---------|----------|",
    ]

    for s in sorted(sessions, key=lambda x: x["created"], reverse=True):
        date = _ms_to_date(s["created"])
        title = _sanitize_table_cell(s["title"][:50])
        msgs = s["message_count"]
        changes = f"+{s['additions']}/-{s['deletions']}"
        duration = _compute_duration(s["created"], s["updated"])
        short_id = s["id"][-8:]
        session_date = _ms_to_date(s["created"])
        link = f"{vault_path}/{CONTEXT_PREFIX}/sessions/{session_date}-{short_id}"
        lines.append(f"| {date} | [[{link}|{title}]] | {msgs} | {changes} | {duration} |")

    lines.append("")
    return "\n".join(lines)


# ============================================================================
# Main Push Logic
# ============================================================================

def push_all(project_filter=None, force=False, dry_run=False, verbose=False):
    stats = {"projects": 0, "created": 0, "updated": 0, "skipped": 0, "errors": 0}

    print(f"\n[Discover] Loading OpenCode projects and sessions...")
    projects = load_projects_and_sessions(project_filter=project_filter)
    stats["projects"] = len(projects)

    total_sessions = sum(len(p["sessions"]) for p in projects)
    print(f"  Found {len(projects)} projects with {total_sessions} sessions")

    if not projects:
        print("  No projects to push.")
        return stats

    if verbose:
        for p in projects:
            print(f"  - {p['vault_path']}: {len(p['sessions'])} sessions")

    # Change detection
    prev_state = {} if force else load_push_state()

    client = create_client(user_agent="opencode-context-push/1.0")
    now_ms = int(datetime.now().timestamp() * 1000)

    with ThreadPoolExecutor(max_workers=10) as executor:
        for project in projects:
            vault_path = project["vault_path"]
            sessions = project["sessions"]
            project_name = project["name"]

            # Filter changed sessions
            changed_sessions = []
            for s in sessions:
                if s["id"] not in prev_state or prev_state[s["id"]] != s["updated"]:
                    changed_sessions.append(s)
                else:
                    stats["skipped"] += 1

            if not changed_sessions and not force:
                continue

            print(f"\n[Push] {vault_path} ({len(changed_sessions)} changed / {len(sessions)} total)")

            # Project index (always when there are changes)
            index_content = generate_project_index(project)
            index_path = f"{vault_path}/{CONTEXT_PREFIX}/INDEX.md"
            result = client.push_content(
                index_path, index_content, now_ms,
                executor=executor, dry_run=dry_run, verbose=verbose,
            )
            stats[result if result in stats else "errors"] += 1

            # Session files
            for session in changed_sessions:
                date_str = _ms_to_date(session["created"])
                short_id = session["id"][-8:]
                session_path = f"{vault_path}/{CONTEXT_PREFIX}/sessions/{date_str}-{short_id}.md"

                content = generate_session_md(session, project_name)
                result = client.push_content(
                    session_path, content, session["updated"],
                    executor=executor, dry_run=dry_run, verbose=verbose,
                )
                stats[result if result in stats else "errors"] += 1

    # Save state after successful push
    if not dry_run and stats["errors"] == 0:
        save_push_state(projects)

    return stats


def main():
    parser = argparse.ArgumentParser(
        description="Push OpenCode session context to Obsidian CouchDB"
    )
    parser.add_argument("--dry-run", action="store_true", help="Preview without uploading")
    parser.add_argument("--force", action="store_true", help="Push all files regardless")
    parser.add_argument("--project", type=str, help="Filter by project name")
    parser.add_argument("-v", "--verbose", action="store_true", help="Verbose output")

    args = parser.parse_args()

    print("=" * 60)
    print("OpenCode Context Push → Obsidian CouchDB")
    print("=" * 60)

    if not OPENCODE_DB.exists():
        print(f"Error: OpenCode database not found: {OPENCODE_DB}", file=sys.stderr)
        sys.exit(1)

    if args.dry_run:
        print("[DRY RUN] No changes will be made")

    try:
        stats = push_all(
            project_filter=args.project,
            force=args.force,
            dry_run=args.dry_run,
            verbose=args.verbose,
        )

        print()
        print("=" * 60)
        print("Summary:")
        print(f"  Projects: {stats['projects']}")
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
