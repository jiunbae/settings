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
import base64
import json
import os
import sqlite3
import sys
import urllib.request
import urllib.error
import urllib.parse
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional
from concurrent.futures import ThreadPoolExecutor, as_completed

import livesync_compat

# ============================================================================
# Configuration
# ============================================================================

VAULT_ROOT = Path.home() / "s-lastorder"
OPENCODE_DB = Path.home() / ".local" / "share" / "opencode" / "opencode.db"
SCRIPT_DIR = Path(__file__).resolve().parent

CONTEXT_PREFIX = "opencode-context"

WORKSPACE_VARIANTS = ["workspace", "workspace-ext", "workspace-vibe",
                      "workspace-game", "workspace-open330"]


def _load_env_file() -> None:
    env_file = SCRIPT_DIR / ".env"
    if not env_file.exists():
        return
    for line in env_file.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip("'\"")
        if key not in os.environ:
            os.environ[key] = value


_load_env_file()

COUCHDB_URI = os.environ.get("COUCHDB_URI", "")
COUCHDB_USER = os.environ.get("COUCHDB_USER", "admin")
COUCHDB_PASSWORD = os.environ.get("COUCHDB_PASSWORD", "")
COUCHDB_DB = os.environ.get("COUCHDB_DB", "obsidian")

MAX_WORKERS = 10


def validate_config() -> None:
    missing = []
    if not COUCHDB_URI:
        missing.append("COUCHDB_URI")
    if not COUCHDB_PASSWORD:
        missing.append("COUCHDB_PASSWORD")
    if missing:
        print(f"Error: {', '.join(missing)} required", file=sys.stderr)
        sys.exit(1)
    if not OPENCODE_DB.exists():
        print(f"Error: OpenCode database not found: {OPENCODE_DB}", file=sys.stderr)
        sys.exit(1)


# ============================================================================
# CouchDB API
# ============================================================================

def couchdb_request(path, method="GET", data=None, timeout=30):
    url = f"{COUCHDB_URI}/{COUCHDB_DB}/{path}"
    body = json.dumps(data).encode('utf-8') if data is not None else None
    req = urllib.request.Request(url, data=body, method=method)
    credentials = base64.b64encode(f"{COUCHDB_USER}:{COUCHDB_PASSWORD}".encode()).decode()
    req.add_header('Authorization', f'Basic {credentials}')
    req.add_header('Content-Type', 'application/json')
    req.add_header('User-Agent', 'opencode-context-push/1.0')
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        if e.code == 409:
            return {"error": "conflict", "reason": "Document update conflict"}
        raw = ""
        try:
            raw = e.read().decode("utf-8", errors="replace").strip()
        except Exception:
            pass
        raise RuntimeError(f"HTTP {e.code}: {e.reason} ({url})\n{raw[:500]}") from e


def couchdb_head(path):
    url = f"{COUCHDB_URI}/{COUCHDB_DB}/{path}"
    req = urllib.request.Request(url, method="HEAD")
    credentials = base64.b64encode(f"{COUCHDB_USER}:{COUCHDB_PASSWORD}".encode()).decode()
    req.add_header('Authorization', f'Basic {credentials}')
    try:
        with urllib.request.urlopen(req, timeout=10):
            return True
    except urllib.error.HTTPError:
        return False


def get_document_rev(doc_id):
    encoded_id = urllib.parse.quote(doc_id, safe='')
    doc = couchdb_request(encoded_id)
    if doc and '_rev' in doc:
        return doc['_rev']
    return None


def put_document(doc):
    doc_id = doc['_id']
    encoded_id = urllib.parse.quote(doc_id, safe='')
    return couchdb_request(encoded_id, method="PUT", data=doc)


def upload_chunk(chunk_id, chunk_data):
    encoded_id = urllib.parse.quote(chunk_id, safe='')
    if couchdb_head(encoded_id):
        return True
    doc = {"_id": chunk_id, "data": chunk_data, "type": "leaf"}
    result = put_document(doc)
    if result and result.get("error") == "conflict":
        return True
    return result is not None and result.get("ok", False)


def push_content(vault_rel_path, content, mtime_ms, dry_run=False, verbose=False):
    chunk_ids, chunks = livesync_compat.process_document(content)

    if dry_run:
        existing = get_document_rev(vault_rel_path)
        action = "UPDATE" if existing else "CREATE"
        print(f"  [{action}] {vault_rel_path} ({len(chunks)} chunks, {len(content)} bytes)")
        return "created" if not existing else "updated"

    failed_chunks = []
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        future_to_idx = {
            executor.submit(upload_chunk, cid, cdata): cid
            for cid, cdata in zip(chunk_ids, chunks)
        }
        for future in as_completed(future_to_idx):
            cid = future_to_idx[future]
            try:
                if not future.result():
                    failed_chunks.append(cid)
            except Exception as e:
                if verbose:
                    print(f"  [WARN] Chunk upload failed {cid}: {e}")
                failed_chunks.append(cid)

    if failed_chunks:
        print(f"  [ERROR] {vault_rel_path}: {len(failed_chunks)} chunks failed")
        return "error"

    file_doc = {
        "_id": vault_rel_path,
        "path": vault_rel_path,
        "children": chunk_ids,
        "ctime": mtime_ms,
        "mtime": mtime_ms,
        "size": len(content.encode("utf-8")),
        "type": "plain",
    }

    existing_rev = get_document_rev(vault_rel_path)
    if existing_rev:
        file_doc["_rev"] = existing_rev

    result = put_document(file_doc)
    if result and result.get("error") == "conflict":
        rev = get_document_rev(vault_rel_path)
        if rev:
            file_doc["_rev"] = rev
            result = put_document(file_doc)

    if result is None or result.get("error"):
        err = result.get("reason", "unknown") if result else "no response"
        print(f"  [ERROR] {vault_rel_path}: {err}")
        return "error"

    action = "UPDATE" if existing_rev else "CREATE"
    if verbose:
        print(f"  [{action}] {vault_rel_path} ({len(chunks)} chunks)")
    return "created" if not existing_rev else "updated"


# ============================================================================
# Session Discovery from SQLite
# ============================================================================

def resolve_vault_path(directory: str) -> Optional[str]:
    """프로젝트 디렉토리 → vault 상대 경로"""
    home = str(Path.home())
    if not directory or not directory.startswith(home):
        return None
    rel = directory[len(home) + 1:]
    for variant in WORKSPACE_VARIANTS:
        if rel.startswith(variant + "/") or rel == variant:
            return rel
    return None


def load_projects_and_sessions(project_filter: Optional[str] = None) -> list[dict]:
    """OpenCode DB에서 프로젝트와 세션 로드"""
    db = sqlite3.connect(str(OPENCODE_DB))
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
        db.close()
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

    # 각 세션의 메시지 수와 첫 프롬프트 가져오기
    if session_ids:
        for sid in session_ids:
            cursor.execute(
                "SELECT COUNT(*) FROM message WHERE session_id = ?", (sid,)
            )
            sessions_map[sid]["message_count"] = cursor.fetchone()[0]

            # 첫 유저 메시지의 텍스트 파트 가져오기
            cursor.execute("""
                SELECT p.data FROM part p
                JOIN message m ON p.message_id = m.id
                WHERE m.session_id = ?
                ORDER BY p.time_created ASC LIMIT 5
            """, (sid,))
            for prow in cursor.fetchall():
                try:
                    pdata = json.loads(prow[0])
                    if pdata.get("type") == "text" and pdata.get("text"):
                        sessions_map[sid]["first_prompt"] = pdata["text"]
                        break
                except (json.JSONDecodeError, KeyError):
                    pass

    db.close()

    # 세션이 있는 프로젝트만 반환
    return [p for p in projects.values() if p["sessions"]]


# ============================================================================
# Markdown Generation
# ============================================================================

def _ms_to_date(ms: int) -> str:
    try:
        return datetime.fromtimestamp(ms / 1000).strftime("%Y-%m-%d")
    except (ValueError, OSError):
        return "unknown"


def _ms_to_datetime(ms: int) -> str:
    try:
        return datetime.fromtimestamp(ms / 1000).strftime("%Y-%m-%d %H:%M")
    except (ValueError, OSError):
        return "unknown"


def _compute_duration(start_ms: int, end_ms: int) -> str:
    total_mins = max(0, (end_ms - start_ms)) // 60000
    if total_mins < 60:
        return f"{total_mins}m"
    hours = total_mins // 60
    mins = total_mins % 60
    return f"{hours}h {mins}m"


def generate_session_md(session: dict, project_name: str) -> str:
    title = session["title"]
    sid = session["id"]
    created = session["created"]
    updated = session["updated"]
    duration = _compute_duration(created, updated)

    lines = [
        "---",
        f"sessionId: {sid}",
        f"tool: opencode",
        f"project: {project_name}",
        f"created: {_ms_to_datetime(created)}",
        f"modified: {_ms_to_datetime(updated)}",
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
        prompt_preview = session["first_prompt"][:500]
        if len(session["first_prompt"]) > 500:
            prompt_preview += "..."
        lines.append(f"> {prompt_preview}")
        lines.append("")

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
        f"tool: opencode",
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
        title = s["title"][:50]
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

    now_ms = int(datetime.now().timestamp() * 1000)

    for project in projects:
        vault_path = project["vault_path"]
        sessions = project["sessions"]
        project_name = project["name"]

        print(f"\n[Push] {vault_path} ({len(sessions) + 1} files)")

        # Project index
        index_content = generate_project_index(project)
        index_path = f"{vault_path}/{CONTEXT_PREFIX}/INDEX.md"
        result = push_content(index_path, index_content, now_ms, dry_run=dry_run, verbose=verbose)
        stats[result if result in stats else "errors"] += 1

        # Session files
        for session in sessions:
            date_str = _ms_to_date(session["created"])
            short_id = session["id"][-8:]
            session_path = f"{vault_path}/{CONTEXT_PREFIX}/sessions/{date_str}-{short_id}.md"

            mtime_ms = session["updated"]

            content = generate_session_md(session, project_name)
            result = push_content(session_path, content, mtime_ms, dry_run=dry_run, verbose=verbose)
            stats[result if result in stats else "errors"] += 1

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

    validate_config()

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
