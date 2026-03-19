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
import base64
import json
import os
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
CODEX_DIR = Path.home() / ".codex"
HISTORY_FILE = CODEX_DIR / "history.jsonl"
CONFIG_FILE = CODEX_DIR / "config.toml"
SCRIPT_DIR = Path(__file__).resolve().parent

CONTEXT_PREFIX = "codex-context"


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

# Workspace 변형
WORKSPACE_VARIANTS = {
    "workspace-ext": "workspace-ext",
    "workspace-vibe": "workspace-vibe",
    "workspace-game": "workspace-game",
    "workspace-open330": "workspace-open330",
    "workspace": "workspace",
}


def validate_config() -> None:
    missing = []
    if not COUCHDB_URI:
        missing.append("COUCHDB_URI")
    if not COUCHDB_PASSWORD:
        missing.append("COUCHDB_PASSWORD")
    if missing:
        env_path = SCRIPT_DIR / ".env"
        print(f"Error: {', '.join(missing)} required", file=sys.stderr)
        sys.exit(1)


# ============================================================================
# CouchDB API (reused from vault-push.py)
# ============================================================================

def couchdb_request(path, method="GET", data=None, timeout=30):
    url = f"{COUCHDB_URI}/{COUCHDB_DB}/{path}"
    body = json.dumps(data).encode('utf-8') if data is not None else None
    req = urllib.request.Request(url, data=body, method=method)
    credentials = base64.b64encode(f"{COUCHDB_USER}:{COUCHDB_PASSWORD}".encode()).decode()
    req.add_header('Authorization', f'Basic {credentials}')
    req.add_header('Content-Type', 'application/json')
    req.add_header('User-Agent', 'codex-context-push/1.0')
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
# Session Discovery
# ============================================================================

def resolve_vault_path_from_config() -> dict[str, str]:
    """config.toml의 trusted projects에서 vault path 매핑 생성"""
    mapping = {}
    if not CONFIG_FILE.exists():
        return mapping

    content = CONFIG_FILE.read_text(encoding="utf-8")
    home = str(Path.home())

    for line in content.splitlines():
        line = line.strip()
        if line.startswith('[projects."') and line.endswith('"]'):
            path = line[len('[projects."'):-len('"]')]
            if path.startswith(home + "/"):
                rel = path[len(home) + 1:]
                # workspace 하위인지 확인
                for prefix in WORKSPACE_VARIANTS:
                    if rel.startswith(prefix + "/") or rel == prefix:
                        mapping[path] = rel
                        break
    return mapping


def load_codex_sessions() -> dict[str, dict]:
    """history.jsonl에서 세션 데이터 로드"""
    sessions = {}
    if not HISTORY_FILE.exists():
        return sessions

    for line in HISTORY_FILE.read_text(encoding="utf-8").splitlines():
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


# ============================================================================
# Markdown Generation
# ============================================================================

def _ts_to_date(ts: int) -> str:
    try:
        return datetime.fromtimestamp(ts).strftime("%Y-%m-%d")
    except (ValueError, OSError):
        return "unknown"


def _ts_to_datetime(ts: int) -> str:
    try:
        return datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M")
    except (ValueError, OSError):
        return "unknown"


def _compute_duration(start_ts: int, end_ts: int) -> str:
    total_mins = max(0, (end_ts - start_ts)) // 60
    if total_mins < 60:
        return f"{total_mins}m"
    hours = total_mins // 60
    mins = total_mins % 60
    return f"{hours}h {mins}m"


def generate_session_md(session: dict) -> str:
    sid = session["id"]
    prompts = session["prompts"]
    ts = session["ts"]
    last_ts = session["last_ts"]

    first_prompt = prompts[0] if prompts else ""
    summary = first_prompt[:80] if first_prompt else "Untitled session"
    duration = _compute_duration(ts, last_ts)

    lines = [
        "---",
        f"sessionId: {sid}",
        f"tool: codex",
        f"created: {_ts_to_datetime(ts)}",
        f"modified: {_ts_to_datetime(last_ts)}",
        f"messageCount: {len(prompts)}",
        "tags: [codex-session, auto-generated]",
        "---",
        "",
        f"# {summary}",
        "",
    ]

    if first_prompt:
        prompt_preview = first_prompt[:500]
        if len(first_prompt) > 500:
            prompt_preview += "..."
        lines.append(f"> {prompt_preview}")
        lines.append("")

    lines.extend([
        f"- **Messages**: {len(prompts)}",
        f"- **Duration**: ~{duration}",
        "",
    ])

    # Show first few prompts
    if len(prompts) > 1:
        lines.append("## Prompts")
        lines.append("")
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
        f"tool: codex",
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
        summary = (s["prompts"][0][:50] if s["prompts"] else "Untitled").replace("\n", " ")
        msgs = len(s["prompts"])
        duration = _compute_duration(s["ts"], s["last_ts"])
        short_id = s["id"][:8]
        session_date = _ts_to_date(s["ts"])
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

    now_ms = int(datetime.now().timestamp() * 1000)
    vault_prefix = CONTEXT_PREFIX

    # Push index
    all_sessions = sorted(sessions.values(), key=lambda x: x["last_ts"], reverse=True)
    index_content = generate_index_md(all_sessions)
    index_path = f"{vault_prefix}/INDEX.md"
    print(f"\n[Push] Index ({len(all_sessions)} sessions)")
    result = push_content(index_path, index_content, now_ms, dry_run=dry_run, verbose=verbose)
    stats[result if result in stats else "errors"] += 1

    # Push individual session files
    print(f"[Push] Session files...")
    for sid, session in sessions.items():
        date_str = _ts_to_date(session["ts"])
        short_id = sid[:8]
        session_path = f"{vault_prefix}/sessions/{date_str}-{short_id}.md"

        mtime_ms = session["last_ts"] * 1000

        content = generate_session_md(session)
        result = push_content(session_path, content, mtime_ms, dry_run=dry_run, verbose=verbose)
        stats[result if result in stats else "errors"] += 1

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

    validate_config()

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
