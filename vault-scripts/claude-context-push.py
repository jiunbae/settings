#!/usr/bin/env python3
"""
Claude Context Push - Claude Code 세션 컨텍스트를 Obsidian CouchDB로 푸시

~/.claude/projects/ 에서 workspace 관련 프로젝트의 세션 메타데이터와
메모리 파일을 마크다운으로 변환하여 CouchDB에 업로드합니다.

푸시되는 데이터:
  - 세션 요약 (sessions-index.json → 개별 마크다운)
  - 메모리 파일 (MEMORY.md 등 → 그대로)
  - 프로젝트 인덱스 (INDEX.md)

사용법:
    python claude-context-push.py                # 변경된 파일만 푸시
    python claude-context-push.py --dry-run      # 미리보기
    python claude-context-push.py --force        # 전부 강제 푸시
    python claude-context-push.py --project settings  # 특정 프로젝트만
    python claude-context-push.py -v             # 상세 출력
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
CLAUDE_PROJECTS_DIR = Path.home() / ".claude" / "projects"
SCRIPT_DIR = Path(__file__).resolve().parent


def _load_env_file() -> None:
    """스크립트 디렉토리의 .env 파일에서 환경변수 로드"""
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

# workspace 관련 프로젝트만 필터링하기 위한 프리픽스
HOME_PREFIX = f"-Users-{Path.home().name}-"

# workspace-* 변형 (top-level dirs)
WORKSPACE_VARIANTS = ["workspace-ext", "workspace-vibe", "workspace-game", "workspace-open330"]


def validate_config() -> None:
    missing = []
    if not COUCHDB_URI:
        missing.append("COUCHDB_URI")
    if not COUCHDB_PASSWORD:
        missing.append("COUCHDB_PASSWORD")
    if missing:
        env_path = SCRIPT_DIR / ".env"
        print(f"Error: {', '.join(missing)} required", file=sys.stderr)
        print(f"\nCreate {env_path} with:", file=sys.stderr)
        print("  COUCHDB_URI=https://your-couchdb-server", file=sys.stderr)
        print("  COUCHDB_PASSWORD=your-password", file=sys.stderr)
        sys.exit(1)


# ============================================================================
# CouchDB API (reused from vault-push.py)
# ============================================================================

def couchdb_request(
    path: str,
    method: str = "GET",
    data: dict = None,
    timeout: int = 30
) -> Optional[dict]:
    url = f"{COUCHDB_URI}/{COUCHDB_DB}/{path}"

    body = None
    if data is not None:
        body = json.dumps(data).encode('utf-8')

    req = urllib.request.Request(url, data=body, method=method)
    credentials = base64.b64encode(
        f"{COUCHDB_USER}:{COUCHDB_PASSWORD}".encode()
    ).decode()
    req.add_header('Authorization', f'Basic {credentials}')
    req.add_header('Content-Type', 'application/json')
    req.add_header('User-Agent', 'claude-context-push/1.0')

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


def couchdb_head(path: str) -> bool:
    url = f"{COUCHDB_URI}/{COUCHDB_DB}/{path}"
    req = urllib.request.Request(url, method="HEAD")
    credentials = base64.b64encode(
        f"{COUCHDB_USER}:{COUCHDB_PASSWORD}".encode()
    ).decode()
    req.add_header('Authorization', f'Basic {credentials}')

    try:
        with urllib.request.urlopen(req, timeout=10):
            return True
    except urllib.error.HTTPError:
        return False


def get_document_rev(doc_id: str) -> Optional[str]:
    encoded_id = urllib.parse.quote(doc_id, safe='')
    doc = couchdb_request(encoded_id)
    if doc and '_rev' in doc:
        return doc['_rev']
    return None


def put_document(doc: dict) -> dict:
    doc_id = doc['_id']
    encoded_id = urllib.parse.quote(doc_id, safe='')
    return couchdb_request(encoded_id, method="PUT", data=doc)


def upload_chunk(chunk_id: str, chunk_data: str) -> bool:
    encoded_id = urllib.parse.quote(chunk_id, safe='')
    if couchdb_head(encoded_id):
        return True
    doc = {"_id": chunk_id, "data": chunk_data, "type": "leaf"}
    result = put_document(doc)
    if result and result.get("error") == "conflict":
        return True
    return result is not None and result.get("ok", False)


# ============================================================================
# Project Discovery & Path Resolution
# ============================================================================

def resolve_vault_path(project_dir: Path) -> Optional[str]:
    """
    Claude 프로젝트 디렉토리 → vault 상대 경로 변환.

    1순위: sessions-index.json의 projectPath 사용
    2순위: 디렉토리명에서 파싱 + 파일시스템 확인
    """
    # 1순위: sessions-index.json에서 projectPath 가져오기
    idx_file = project_dir / "sessions-index.json"
    if idx_file.exists():
        try:
            data = json.load(open(idx_file))
            for entry in data.get("entries", []):
                pp = entry.get("projectPath", "")
                if pp:
                    home = str(Path.home())
                    if pp.startswith(home):
                        return pp[len(home):].lstrip("/")
        except (json.JSONDecodeError, KeyError):
            pass

    # 2순위: 디렉토리명에서 파싱
    name = project_dir.name
    if not name.startswith(HOME_PREFIX):
        return None

    remainder = name[len(HOME_PREFIX):]  # e.g., "workspace-settings" or "workspace-ext-aily"

    # workspace-* 변형 체크
    for variant in WORKSPACE_VARIANTS:
        prefix = variant.replace("-", "-")  # workspace-ext
        dir_prefix = prefix.replace("/", "-")
        if remainder.startswith(dir_prefix + "-"):
            subname = remainder[len(dir_prefix) + 1:]
            candidate = Path.home() / variant / subname
            # 하이픈이 포함된 이름 복원 시도
            if candidate.exists():
                return f"{variant}/{subname}"
            # 하이픈으로 구분된 경로 시도
            parts = subname.split("-")
            for i in range(len(parts), 0, -1):
                dir_name = "-".join(parts[:i])
                rest = "/".join(parts[i:]) if i < len(parts) else ""
                test = Path.home() / variant / dir_name
                if test.exists():
                    return f"{variant}/{dir_name}/{rest}".rstrip("/")
            return f"{variant}/{subname}"
        elif remainder == dir_prefix:
            return variant

    # 일반 workspace 하위 디렉토리
    if remainder.startswith("workspace-"):
        subname = remainder[len("workspace-"):]
        # 직접 매칭 시도
        candidate = Path.home() / "workspace" / subname
        if candidate.exists():
            return f"workspace/{subname}"
        # 하이픈으로 구분된 경로 시도 (settings-vault-scripts → settings/vault-scripts)
        parts = subname.split("-")
        for i in range(len(parts), 0, -1):
            dir_name = "-".join(parts[:i])
            rest = "/".join(parts[i:]) if i < len(parts) else ""
            test = Path.home() / "workspace" / dir_name
            if test.exists() and test.is_dir():
                return f"workspace/{dir_name}/{rest}".rstrip("/")
        return f"workspace/{subname}"
    elif remainder == "workspace":
        return "workspace"

    return None


def discover_projects(project_filter: Optional[str] = None) -> list[dict]:
    """
    ~/.claude/projects/ 에서 workspace 관련 프로젝트 탐색.

    Returns: [{dir, vault_path, sessions_index, memory_files, claude_md}, ...]
    """
    projects = []

    if not CLAUDE_PROJECTS_DIR.exists():
        print("  No Claude projects directory found.", file=sys.stderr)
        return projects

    for proj_dir in sorted(CLAUDE_PROJECTS_DIR.iterdir()):
        if not proj_dir.is_dir():
            continue
        if "workspace" not in proj_dir.name:
            continue
        # 캐시/worktree 디렉토리 제외
        if "--claude-worktrees" in proj_dir.name:
            continue
        if "__pycache__" in proj_dir.name:
            continue

        vault_path = resolve_vault_path(proj_dir)
        if not vault_path:
            continue

        # 프로젝트 필터 적용
        if project_filter:
            if project_filter not in vault_path and project_filter not in proj_dir.name:
                continue

        # 세션 인덱스 로드
        sessions_index = None
        idx_file = proj_dir / "sessions-index.json"
        if idx_file.exists():
            try:
                sessions_index = json.load(open(idx_file))
            except json.JSONDecodeError:
                pass

        # 메모리 파일 수집
        memory_files = []
        mem_dir = proj_dir / "memory"
        if mem_dir.exists():
            for f in sorted(mem_dir.iterdir()):
                if f.is_file() and f.suffix == ".md":
                    memory_files.append(f)

        # CLAUDE.md 탐색 (실제 워크스페이스 디렉토리에서)
        claude_md = None
        real_path = Path.home() / vault_path
        if real_path.exists():
            cmd_file = real_path / "CLAUDE.md"
            if cmd_file.exists():
                claude_md = cmd_file

        # 데이터가 있는 프로젝트만
        entries = sessions_index.get("entries", []) if sessions_index else []
        if not entries and not memory_files and not claude_md:
            continue

        project_name = vault_path.split("/")[-1] if "/" in vault_path else vault_path

        projects.append({
            "dir": proj_dir,
            "vault_path": vault_path,
            "project_name": project_name,
            "sessions_index": sessions_index,
            "entries": entries,
            "memory_files": memory_files,
            "claude_md": claude_md,
        })

    return projects


# ============================================================================
# Markdown Generation
# ============================================================================

def _format_datetime(iso_str: str) -> str:
    """ISO datetime → 'YYYY-MM-DD HH:MM' format"""
    try:
        dt = datetime.fromisoformat(iso_str.replace("Z", "+00:00"))
        return dt.strftime("%Y-%m-%d %H:%M")
    except (ValueError, AttributeError):
        return str(iso_str)[:16]


def _format_date(iso_str: str) -> str:
    """ISO datetime → 'YYYY-MM-DD' format"""
    try:
        dt = datetime.fromisoformat(iso_str.replace("Z", "+00:00"))
        return dt.strftime("%Y-%m-%d")
    except (ValueError, AttributeError):
        return str(iso_str)[:10]


def _compute_duration(created: str, modified: str) -> str:
    """두 ISO datetime 사이의 시간 차이 계산"""
    try:
        c = datetime.fromisoformat(created.replace("Z", "+00:00"))
        m = datetime.fromisoformat(modified.replace("Z", "+00:00"))
        delta = m - c
        total_mins = int(delta.total_seconds() / 60)
        if total_mins < 60:
            return f"{total_mins}m"
        hours = total_mins // 60
        mins = total_mins % 60
        return f"{hours}h {mins}m"
    except (ValueError, AttributeError):
        return "?"


def generate_session_md(entry: dict, project_name: str) -> str:
    """세션 엔트리 → 마크다운 문서 생성"""
    session_id = entry.get("sessionId", "unknown")
    summary = entry.get("summary", "Untitled session")
    first_prompt = entry.get("firstPrompt", "")
    msg_count = entry.get("messageCount", 0)
    created = entry.get("created", "")
    modified = entry.get("modified", "")
    branch = entry.get("gitBranch", "")
    is_sidechain = entry.get("isSidechain", False)

    duration = _compute_duration(created, modified) if created and modified else ""

    lines = [
        "---",
        f"sessionId: {session_id}",
        f"project: {project_name}",
        f"created: {_format_datetime(created)}",
        f"modified: {_format_datetime(modified)}",
        f"messageCount: {msg_count}",
    ]
    if branch:
        lines.append(f"gitBranch: {branch}")
    if is_sidechain:
        lines.append("isSidechain: true")
    lines.extend([
        "tags: [claude-session, auto-generated]",
        "---",
        "",
        f"# {summary}",
        "",
    ])

    if first_prompt:
        # 첫 프롬프트를 인용 블록으로
        prompt_preview = first_prompt[:500]
        if len(first_prompt) > 500:
            prompt_preview += "..."
        lines.append(f"> {prompt_preview}")
        lines.append("")

    lines.extend([
        f"- **Messages**: {msg_count}",
    ])
    if branch:
        lines.append(f"- **Branch**: `{branch}`")
    if duration:
        lines.append(f"- **Duration**: ~{duration}")
    if is_sidechain:
        lines.append("- **Sidechain**: yes")

    lines.append("")
    return "\n".join(lines)


def generate_project_index(project: dict) -> str:
    """프로젝트 컨텍스트 인덱스 마크다운 생성"""
    vault_path = project["vault_path"]
    project_name = project["project_name"]
    entries = project["entries"]
    memory_files = project["memory_files"]
    now = datetime.now().strftime("%Y-%m-%dT%H:%M:%S")

    lines = [
        "---",
        f"project: {project_name}",
        f"updated: {now}",
        "tags: [claude-context, index, auto-generated]",
        "---",
        "",
        f"# Claude Context: {project_name}",
        "",
    ]

    # 세션 테이블
    if entries:
        lines.append(f"## Sessions ({len(entries)})")
        lines.append("")
        lines.append("| Date | Summary | Messages | Duration |")
        lines.append("|------|---------|----------|----------|")
        for entry in sorted(entries, key=lambda e: e.get("created", ""), reverse=True):
            date = _format_date(entry.get("created", ""))
            summary = entry.get("summary", "Untitled")
            msgs = entry.get("messageCount", 0)
            duration = _compute_duration(
                entry.get("created", ""),
                entry.get("modified", "")
            )
            session_id = entry.get("sessionId", "")[:8]
            # Obsidian 링크
            session_date = _format_date(entry.get("created", ""))
            link_target = f"{vault_path}/claude-context/sessions/{session_date}-{session_id}"
            lines.append(
                f"| {date} | [[{link_target}|{summary}]] | {msgs} | {duration} |"
            )
        lines.append("")

    # 메모리 파일
    if memory_files:
        lines.append(f"## Memory ({len(memory_files)} files)")
        lines.append("")
        for mf in memory_files:
            link_target = f"{vault_path}/claude-context/memory/{mf.name}"
            lines.append(f"- [[{link_target}|{mf.name}]]")
        lines.append("")

    # CLAUDE.md
    if project["claude_md"]:
        lines.append("## CLAUDE.md")
        lines.append("")
        link_target = f"{vault_path}/claude-context/CLAUDE.md"
        lines.append(f"- [[{link_target}|CLAUDE.md]]")
        lines.append("")

    return "\n".join(lines)


# ============================================================================
# File Push (reused pattern from vault-push.py)
# ============================================================================

def push_content(
    vault_rel_path: str,
    content: str,
    mtime_ms: int,
    dry_run: bool = False,
    verbose: bool = False,
) -> str:
    """
    콘텐츠를 CouchDB에 푸시.

    Returns: "created", "updated", "skipped", "error"
    """
    chunk_ids, chunks = livesync_compat.process_document(content)

    if dry_run:
        existing = get_document_rev(vault_rel_path)
        action = "UPDATE" if existing else "CREATE"
        print(f"  [{action}] {vault_rel_path} ({len(chunks)} chunks, {len(content)} bytes)")
        return "created" if not existing else "updated"

    # 청크 업로드
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

    # 파일 문서 빌드
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
# Remote Document Fetching (for change detection)
# ============================================================================

def get_remote_context_mtimes(prefix: str = "workspace") -> dict[str, int]:
    """
    CouchDB에서 claude-context 문서의 mtime 가져오기.

    Returns: {path: mtime_ms}
    """
    mtimes = {}
    start_key = urllib.parse.quote(json.dumps(f"{prefix}/"), safe='')
    end_key = urllib.parse.quote(json.dumps(f"{prefix}/\ufff0"), safe='')
    query = f'_all_docs?include_docs=true&startkey={start_key}&endkey={end_key}'

    result = couchdb_request(query)
    if not result:
        return mtimes

    for row in result.get('rows', []):
        doc = row.get('doc', {})
        doc_id = doc.get('_id', '')
        if 'claude-context' in doc_id and ('children' in doc or 'data' in doc):
            mtime = doc.get('mtime', 0)
            if isinstance(mtime, str):
                try:
                    mtime = int(mtime)
                except ValueError:
                    mtime = 0
            mtimes[doc_id] = mtime

    return mtimes


# ============================================================================
# Main Push Logic
# ============================================================================

def push_project_context(
    project: dict,
    remote_mtimes: dict[str, int],
    force: bool = False,
    dry_run: bool = False,
    verbose: bool = False,
) -> dict:
    """단일 프로젝트의 Claude 컨텍스트를 CouchDB에 푸시"""

    stats = {"created": 0, "updated": 0, "skipped": 0, "errors": 0}
    vault_path = project["vault_path"]
    project_name = project["project_name"]
    entries = project["entries"]
    now_ms = int(datetime.now().timestamp() * 1000)

    # 1) 프로젝트 인덱스
    index_content = generate_project_index(project)
    index_path = f"{vault_path}/claude-context/INDEX.md"
    result = push_content(index_path, index_content, now_ms, dry_run=dry_run, verbose=verbose)
    stats[result if result in stats else "errors"] += 1

    # 2) 세션 요약 파일들
    for entry in entries:
        session_id = entry.get("sessionId", "unknown")
        created = entry.get("created", "")
        modified = entry.get("modified", "")
        date_str = _format_date(created)
        short_id = session_id[:8]

        session_path = f"{vault_path}/claude-context/sessions/{date_str}-{short_id}.md"

        # 변경 감지: modified 시간을 mtime으로 사용
        try:
            mtime_ms = int(
                datetime.fromisoformat(
                    modified.replace("Z", "+00:00")
                ).timestamp() * 1000
            )
        except (ValueError, AttributeError):
            mtime_ms = now_ms

        if not force and session_path in remote_mtimes:
            if remote_mtimes[session_path] >= mtime_ms:
                if verbose:
                    print(f"  [SKIP] {session_path} (not changed)")
                stats["skipped"] += 1
                continue

        content = generate_session_md(entry, project_name)
        result = push_content(session_path, content, mtime_ms, dry_run=dry_run, verbose=verbose)
        stats[result if result in stats else "errors"] += 1

    # 3) 메모리 파일
    for mem_file in project["memory_files"]:
        mem_vault_path = f"{vault_path}/claude-context/memory/{mem_file.name}"

        try:
            content = mem_file.read_text(encoding="utf-8")
            mtime_ms = int(mem_file.stat().st_mtime * 1000)
        except Exception as e:
            print(f"  [ERROR] {mem_vault_path}: {e}")
            stats["errors"] += 1
            continue

        if not force and mem_vault_path in remote_mtimes:
            if remote_mtimes[mem_vault_path] >= mtime_ms:
                if verbose:
                    print(f"  [SKIP] {mem_vault_path} (not changed)")
                stats["skipped"] += 1
                continue

        result = push_content(mem_vault_path, content, mtime_ms, dry_run=dry_run, verbose=verbose)
        stats[result if result in stats else "errors"] += 1

    # 4) CLAUDE.md
    if project["claude_md"]:
        claude_vault_path = f"{vault_path}/claude-context/CLAUDE.md"
        try:
            content = project["claude_md"].read_text(encoding="utf-8")
            mtime_ms = int(project["claude_md"].stat().st_mtime * 1000)
        except Exception as e:
            print(f"  [ERROR] {claude_vault_path}: {e}")
            stats["errors"] += 1
        else:
            if not force and claude_vault_path in remote_mtimes:
                if remote_mtimes[claude_vault_path] >= mtime_ms:
                    if verbose:
                        print(f"  [SKIP] {claude_vault_path} (not changed)")
                    stats["skipped"] += 1
                else:
                    result = push_content(
                        claude_vault_path, content, mtime_ms,
                        dry_run=dry_run, verbose=verbose
                    )
                    stats[result if result in stats else "errors"] += 1
            else:
                result = push_content(
                    claude_vault_path, content, mtime_ms,
                    dry_run=dry_run, verbose=verbose
                )
                stats[result if result in stats else "errors"] += 1

    return stats


def push_all(
    project_filter: Optional[str] = None,
    force: bool = False,
    dry_run: bool = False,
    verbose: bool = False,
) -> dict:
    """모든 workspace 프로젝트의 Claude 컨텍스트를 푸시"""

    total_stats = {
        "projects": 0,
        "created": 0,
        "updated": 0,
        "skipped": 0,
        "errors": 0,
    }

    print(f"\n[Discover] Scanning Claude projects...")
    projects = discover_projects(project_filter=project_filter)
    total_stats["projects"] = len(projects)
    print(f"  Found {len(projects)} workspace projects with context data")

    if not projects:
        print("  No projects to push.")
        return total_stats

    if verbose:
        for p in projects:
            n_sessions = len(p["entries"])
            n_memory = len(p["memory_files"])
            has_claude = "yes" if p["claude_md"] else "no"
            print(f"  - {p['vault_path']}: {n_sessions} sessions, {n_memory} memory, CLAUDE.md={has_claude}")

    # 리모트 mtime 가져오기 (변경 감지용)
    remote_mtimes = {}
    if not force:
        print(f"\n[Remote] Fetching existing context document mtimes...")
        # workspace 및 workspace-* 프리픽스에 대해 조회
        seen_prefixes = set()
        for p in projects:
            prefix = p["vault_path"].split("/")[0]
            seen_prefixes.add(prefix)
        for prefix in seen_prefixes:
            remote_mtimes.update(get_remote_context_mtimes(prefix))
        print(f"  Existing context documents: {len(remote_mtimes)}")

    # 프로젝트별 푸시
    print()
    for project in projects:
        vault_path = project["vault_path"]
        n_items = len(project["entries"]) + len(project["memory_files"])
        if project["claude_md"]:
            n_items += 1
        n_items += 1  # INDEX.md

        print(f"[Push] {vault_path} ({n_items} files)")

        stats = push_project_context(
            project,
            remote_mtimes=remote_mtimes,
            force=force,
            dry_run=dry_run,
            verbose=verbose,
        )

        total_stats["created"] += stats["created"]
        total_stats["updated"] += stats["updated"]
        total_stats["skipped"] += stats["skipped"]
        total_stats["errors"] += stats["errors"]

    return total_stats


# ============================================================================
# CLI
# ============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Push Claude Code session context to Obsidian CouchDB"
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="Preview without uploading"
    )
    parser.add_argument(
        "--force", action="store_true",
        help="Push all files regardless of mtime"
    )
    parser.add_argument(
        "--project", type=str,
        help="Filter by project name (e.g., 'settings', 'agent-skills')"
    )
    parser.add_argument(
        "-v", "--verbose", action="store_true",
        help="Verbose output"
    )

    args = parser.parse_args()

    print("=" * 60)
    print("Claude Context Push → Obsidian CouchDB")
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
