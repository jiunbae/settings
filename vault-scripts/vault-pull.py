#!/usr/bin/env python3
"""
Obsidian Vault Pull - CouchDB에서 문서 가져오기

Obsidian LiveSync 플러그인보다 빠른 CLI 기반 pull 스크립트입니다.
LiveSync와 동일한 청크 포맷을 사용하여 호환성을 유지합니다.

사용법:
    # 전체 pull
    python vault-pull.py

    # 미리보기
    python vault-pull.py --dry-run

    # 특정 경로만
    python vault-pull.py --path workspace/ssudam

    # 변경된 파일만 (mtime 기준)
    python vault-pull.py --changed-only

    # 로컬에만 있는 orphan 파일 삭제 (CouchDB에 없는 파일)
    python vault-pull.py --delete-orphans

    # orphan 파일 미리보기
    python vault-pull.py --delete-orphans --dry-run
"""

import argparse
import base64
import json
import os
import sys
import urllib.request
import urllib.error
import urllib.parse
from datetime import datetime
from pathlib import Path
from typing import Optional

# ============================================================================
# Configuration
# ============================================================================

VAULT_ROOT = Path.home() / "s-lastorder"
SCRIPT_DIR = Path(__file__).resolve().parent

def _load_env_file() -> None:
    """스크립트 디렉토리의 .env 파일에서 환경변수 로드 (기존 값 덮어쓰지 않음)"""
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

# CouchDB 설정 (환경변수 → .env → 기본값)
COUCHDB_URI = os.environ.get("COUCHDB_URI", "https://your-couchdb-server")
COUCHDB_USER = os.environ.get("COUCHDB_USER", "admin")
COUCHDB_PASSWORD = os.environ.get("COUCHDB_PASSWORD", "")
COUCHDB_DB = os.environ.get("COUCHDB_DB", "obsidian")

# 제외 패턴
EXCLUDE_PATTERNS = [
    ".obsidian/",
    ".git/",
    ".DS_Store",
    "node_modules/",
    "scripts/",
]


def print_env_diagnostics() -> None:
    """Print env-related diagnostics (never prints secrets)."""
    print("\n[Env Diagnostics]")
    print(f"  cwd: {os.getcwd()}")
    print(f"  python: {sys.executable}")
    print(f"  platform: {sys.platform}")

    def _mask_len(name: str) -> None:
        val = os.environ.get(name)
        present = val is not None
        length = len(val or "")
        print(f"  {name}: present={present} len={length}")

    _mask_len("COUCHDB_URI")
    _mask_len("COUCHDB_USER")
    _mask_len("COUCHDB_PASSWORD")
    _mask_len("COUCHDB_DB")

    # Common env vars that affect uv / venvs / dotenv behavior.
    for name in [
        "UV_ENV_FILE",
        "UV_NO_ENV_FILE",
        "VIRTUAL_ENV",
        "CONDA_PREFIX",
        "PYTHONPATH",
    ]:
        val = os.environ.get(name)
        if val:
            print(f"  {name}: {val}")


def validate_config() -> None:
    if not COUCHDB_PASSWORD:
        env_path = SCRIPT_DIR / ".env"
        print("Error: COUCHDB_PASSWORD is required", file=sys.stderr)
        print(f"\nCreate {env_path} with:", file=sys.stderr)
        print("  COUCHDB_PASSWORD=your-password", file=sys.stderr)
        print("\nOr set environment variable:", file=sys.stderr)
        if os.name == "nt":
            print("  PowerShell: $env:COUCHDB_PASSWORD='your-password'", file=sys.stderr)
        else:
            print("  export COUCHDB_PASSWORD='your-password'", file=sys.stderr)
        sys.exit(1)


def couchdb_request(path: str, method: str = "GET", data: dict = None, timeout: int = 30) -> dict:
    """CouchDB API 요청"""
    url = f"{COUCHDB_URI}/{COUCHDB_DB}/{path}"

    if data:
        req = urllib.request.Request(
            url,
            data=json.dumps(data).encode('utf-8'),
            method=method
        )
    else:
        req = urllib.request.Request(url, method=method)

    credentials = base64.b64encode(f"{COUCHDB_USER}:{COUCHDB_PASSWORD}".encode()).decode()
    req.add_header('Authorization', f'Basic {credentials}')
    req.add_header('Content-Type', 'application/json')
    req.add_header('User-Agent', 'vault-pull/1.0')

    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        body = ""
        try:
            raw = e.read()
            if raw:
                body = raw.decode("utf-8", errors="replace").strip()
        except Exception:
            body = ""

        msg = f"HTTP Error {e.code}: {e.reason} ({url})"
        if body:
            if len(body) > 2000:
                body = body[:2000] + "...<truncated>"
            msg += f"\nResponse body: {body}"
        raise RuntimeError(msg) from e


def get_all_documents(path_filter: Optional[str] = None) -> list[dict]:
    """
    모든 문서 메타데이터 가져오기 (청크 제외)

    CouchDB에서 파일 문서만 가져옵니다.
    - 청크 문서 (h:로 시작)는 제외
    - 두 번의 쿼리로 청크 전후 문서 가져오기
    """
    documents = []

    if path_filter:
        # 특정 경로로 시작하는 문서만
        start_key = urllib.parse.quote(json.dumps(path_filter), safe='')
        end_key = urllib.parse.quote(json.dumps(f"{path_filter}\ufff0"), safe='')
        queries = [f"_all_docs?include_docs=true&startkey={start_key}&endkey={end_key}"]
    else:
        # 청크(h:)를 제외하기 위해 두 범위로 나눔:
        # 1. 처음 ~ "h:" (inclusive)
        # 2. "h;" ~ 끝 ("h;"는 "h:" 바로 다음 → 모든 h:* 청크를 건너뜀)
        end_key = urllib.parse.quote(json.dumps("h:"), safe='')
        start_key = urllib.parse.quote(json.dumps("h;"), safe='')  # ';' sorts right after ':'.
        queries = [
            f'_all_docs?include_docs=true&endkey={end_key}',  # 처음 ~ "h:"
            f'_all_docs?include_docs=true&startkey={start_key}',  # "h;" ~ 끝
        ]

    for query in queries:
        print(f"  Query: {query}")
        result = couchdb_request(query)

        for row in result.get('rows', []):
            doc = row.get('doc', {})
            doc_id = doc.get('_id', '')

            # 청크 문서 제외 (h:로 시작)
            if doc_id.startswith('h:'):
                continue

            # 디자인 문서 제외
            if doc_id.startswith('_'):
                continue

            # 파일 문서: children(chunked) 또는 data(plain) 필드가 있는 문서
            if 'children' in doc or 'data' in doc:
                documents.append(doc)

    return documents


def batch_fetch_chunks(chunk_ids: list[str], batch_size: int = 500) -> dict[str, str]:
    """Batch fetch chunk data from CouchDB using _all_docs POST with keys."""
    if not chunk_ids:
        return {}

    chunk_cache: dict[str, str] = {}
    total = len(chunk_ids)

    for i in range(0, total, batch_size):
        batch = chunk_ids[i:i + batch_size]
        batch_num = i // batch_size + 1
        total_batches = (total + batch_size - 1) // batch_size
        print(f"  Batch {batch_num}/{total_batches} ({len(batch)} chunks)...")

        result = couchdb_request(
            "_all_docs?include_docs=true",
            method="POST",
            data={"keys": batch},
            timeout=120,
        )

        if not result:
            print(f"  Warning: Batch {batch_num} returned no result", file=sys.stderr)
            continue

        for row in result.get('rows', []):
            if 'error' in row:
                continue
            doc = row.get('doc')
            if doc and '_id' in doc:
                chunk_cache[doc['_id']] = doc.get('data', '')

    return chunk_cache


def try_decode_base64(content: str) -> tuple:
    """
    Detect and decode base64-encoded content from LiveSync.

    LiveSync stores non-markdown files (e.g. .py, images) as base64.
    Base64 content from LiveSync is always a single line (no newlines).

    Returns: (decoded_content, is_binary)
      - is_binary=False: content is str (text)
      - is_binary=True: content is bytes (binary)
    """
    # Multi-line content is plain text
    if '\n' in content or len(content) < 4:
        return content, False

    # Try strict base64 decode
    try:
        decoded = base64.b64decode(content, validate=True)
    except Exception:
        return content, False

    # Try to interpret as UTF-8 text
    try:
        return decoded.decode('utf-8'), False
    except UnicodeDecodeError:
        return decoded, True


def should_exclude(path: str) -> bool:
    """제외 패턴 확인"""
    for pattern in EXCLUDE_PATTERNS:
        if pattern in path:
            return True
    return False


# ============================================================================
# Orphan Detection & Deletion
# ============================================================================

# 동기화 대상 디렉토리 (이 디렉토리 내의 파일만 orphan 검사)
SYNC_DIRECTORIES = [
    "workspace",
    "workspace-vibe",
    "workspace-ext",
    "articles",
    "Notes",
    "TaskManager",
]


def get_local_files(path_filter: Optional[str] = None) -> set[str]:
    """로컬 vault의 모든 파일 경로 수집"""
    local_files = set()

    for sync_dir in SYNC_DIRECTORIES:
        dir_path = VAULT_ROOT / sync_dir
        if not dir_path.exists():
            continue

        # path_filter가 있으면 해당 디렉토리만
        if path_filter and not sync_dir.startswith(path_filter.split('/')[0]):
            continue

        for file_path in dir_path.rglob('*'):
            if file_path.is_file():
                rel_path = str(file_path.relative_to(VAULT_ROOT))

                # 제외 패턴 확인
                if should_exclude(rel_path):
                    continue

                # path_filter 적용
                if path_filter and not rel_path.startswith(path_filter):
                    continue

                local_files.add(rel_path)

    return local_files


def find_orphan_files(
    path_filter: Optional[str] = None,
    verbose: bool = False
) -> list[str]:
    """CouchDB에 없는 로컬 파일 찾기"""

    print(f"\n[Orphan Detection] Comparing local files with CouchDB...")

    # CouchDB 문서 ID 수집
    documents = get_all_documents(path_filter=path_filter)
    remote_paths = set()

    for doc in documents:
        doc_id = doc.get('_id', '')
        doc_path = doc.get('path', doc_id)
        if doc_path.startswith('/'):
            doc_path = doc_path[1:]
        remote_paths.add(doc_path)

    print(f"  Remote documents: {len(remote_paths)}")

    # 로컬 파일 수집
    local_files = get_local_files(path_filter=path_filter)
    print(f"  Local files: {len(local_files)}")

    # Orphan 파일 = 로컬에만 있는 파일
    orphans = sorted(local_files - remote_paths)
    print(f"  Orphan files: {len(orphans)}")

    return orphans


def delete_orphan_files(
    path_filter: Optional[str] = None,
    dry_run: bool = False,
    verbose: bool = False
) -> dict:
    """CouchDB에 없는 로컬 파일 삭제"""

    stats = {
        'found': 0,
        'deleted': 0,
        'errors': 0,
    }

    orphans = find_orphan_files(path_filter=path_filter, verbose=verbose)
    stats['found'] = len(orphans)

    if not orphans:
        print("\n  No orphan files found.")
        return stats

    print(f"\n[Delete Orphans] Processing {len(orphans)} files...")

    for rel_path in orphans:
        file_path = VAULT_ROOT / rel_path

        if dry_run:
            print(f"  [DELETE] {rel_path}")
            stats['deleted'] += 1
        else:
            try:
                if file_path.exists():
                    file_path.unlink()
                    if verbose:
                        print(f"  [DELETE] {rel_path}")
                    stats['deleted'] += 1

                    # 빈 디렉토리 정리
                    parent = file_path.parent
                    while parent != VAULT_ROOT:
                        if parent.exists() and not any(parent.iterdir()):
                            parent.rmdir()
                            if verbose:
                                print(f"  [RMDIR] {parent.relative_to(VAULT_ROOT)}")
                        parent = parent.parent
            except Exception as e:
                print(f"  [ERROR] {rel_path}: {e}")
                stats['errors'] += 1

    return stats


def pull_documents(
    path_filter: Optional[str] = None,
    changed_only: bool = False,
    dry_run: bool = False,
    verbose: bool = False
) -> dict:
    """CouchDB에서 문서 pull (batch chunk fetching)"""

    stats = {
        'total': 0,
        'created': 0,
        'updated': 0,
        'skipped': 0,
        'errors': 0,
    }

    print(f"\n[Pull] Fetching documents from CouchDB...")
    print(f"  URI: {COUCHDB_URI}/{COUCHDB_DB}")
    if path_filter:
        print(f"  Filter: {path_filter}")

    documents = get_all_documents(path_filter=path_filter)
    stats['total'] = len(documents)
    print(f"  Total documents: {len(documents)}")

    # Phase 1: Filter documents (exclude patterns, mtime check)
    docs_to_pull = []
    for doc in documents:
        doc_id = doc.get('_id', '')
        doc_path = doc.get('path', doc_id)

        if doc_path.startswith('/'):
            doc_path = doc_path[1:]

        if should_exclude(doc_path):
            if verbose:
                print(f"  [SKIP] {doc_path} (excluded)")
            stats['skipped'] += 1
            continue

        local_path = VAULT_ROOT / doc_path

        if changed_only and local_path.exists():
            local_mtime = datetime.fromtimestamp(local_path.stat().st_mtime)
            remote_mtime_str = doc.get('mtime', '')
            if remote_mtime_str:
                try:
                    if 'T' in str(remote_mtime_str):
                        remote_mtime = datetime.fromisoformat(remote_mtime_str.replace('Z', '+00:00'))
                    else:
                        remote_mtime = datetime.fromtimestamp(int(remote_mtime_str) / 1000)
                    if remote_mtime <= local_mtime:
                        if verbose:
                            print(f"  [SKIP] {doc_path} (not changed)")
                        stats['skipped'] += 1
                        continue
                except:
                    pass

        docs_to_pull.append((doc, doc_path, local_path))

    print(f"  To pull: {len(docs_to_pull)}  Skipped: {stats['skipped']}")

    # Phase 2: Collect all chunk IDs
    all_chunk_ids = []
    seen_ids: set[str] = set()
    for doc, _, _ in docs_to_pull:
        for chunk_id in doc.get('children', []):
            if chunk_id not in seen_ids:
                all_chunk_ids.append(chunk_id)
                seen_ids.add(chunk_id)

    # Phase 3: Batch fetch all chunks
    chunk_cache: dict[str, str] = {}
    if all_chunk_ids:
        print(f"\n[Pull] Fetching {len(all_chunk_ids)} unique chunks...")
        chunk_cache = batch_fetch_chunks(all_chunk_ids)
        print(f"  Cached: {len(chunk_cache)} chunks")

    # Phase 4: Assemble and write files
    print(f"\n[Pull] Writing {len(docs_to_pull)} files...")
    for doc, doc_path, local_path in docs_to_pull:
        children = doc.get('children', [])

        # Assemble content
        if not children:
            content = doc.get('data', '')
        else:
            parts = []
            missing = 0
            for chunk_id in children:
                chunk_data = chunk_cache.get(chunk_id)
                if chunk_data is not None:
                    parts.append(chunk_data)
                else:
                    missing += 1
            if missing:
                print(f"  [WARN] {doc_path}: {missing} missing chunks", file=sys.stderr)
            content = ''.join(parts)

        # Decode base64 if needed (LiveSync stores non-md files as base64)
        content, is_binary = try_decode_base64(content)

        action = "UPDATE" if local_path.exists() else "CREATE"

        if dry_run:
            size = len(content) if isinstance(content, str) else len(content)
            print(f"  [{action}] {doc_path} ({size} bytes)")
        else:
            try:
                local_path.parent.mkdir(parents=True, exist_ok=True)
                if is_binary:
                    local_path.write_bytes(content)
                else:
                    local_path.write_text(content, encoding='utf-8')

                # mtime 설정
                mtime_str = doc.get('mtime', '')
                if mtime_str:
                    try:
                        if 'T' in str(mtime_str):
                            mtime = datetime.fromisoformat(mtime_str.replace('Z', '+00:00')).timestamp()
                        else:
                            mtime = int(mtime_str) / 1000
                        os.utime(local_path, (mtime, mtime))
                    except:
                        pass

                if verbose:
                    print(f"  [{action}] {doc_path}")
            except Exception as e:
                print(f"  [ERROR] {doc_path}: {e}")
                stats['errors'] += 1
                continue

        if action == "CREATE":
            stats['created'] += 1
        else:
            stats['updated'] += 1

    return stats


def main():
    parser = argparse.ArgumentParser(description="Pull documents from CouchDB")
    parser.add_argument('--dry-run', action='store_true', help='Preview without writing')
    parser.add_argument('--path', type=str, help='Filter by path prefix')
    parser.add_argument('--changed-only', action='store_true', help='Only pull changed files')
    parser.add_argument('--delete-orphans', action='store_true',
                        help='Delete local files not in CouchDB (orphan cleanup)')
    parser.add_argument('-v', '--verbose', action='store_true', help='Verbose output')
    parser.add_argument('--print-env', action='store_true',
                        help='Print env diagnostics (does not print secrets) and exit')

    args = parser.parse_args()

    print("=" * 60)
    print("Obsidian Vault Pull")
    print("=" * 60)

    if args.print_env:
        print_env_diagnostics()
        return

    validate_config()

    if args.dry_run:
        print("[DRY RUN] No changes will be made")

    try:
        # Pull documents
        stats = pull_documents(
            path_filter=args.path,
            changed_only=args.changed_only,
            dry_run=args.dry_run,
            verbose=args.verbose
        )

        # Delete orphans if requested
        orphan_stats = None
        if args.delete_orphans:
            orphan_stats = delete_orphan_files(
                path_filter=args.path,
                dry_run=args.dry_run,
                verbose=args.verbose
            )

        print()
        print("=" * 60)
        print("Summary:")
        print(f"  Total documents: {stats['total']}")
        print(f"  Created: {stats['created']}")
        print(f"  Updated: {stats['updated']}")
        print(f"  Skipped: {stats['skipped']}")
        print(f"  Errors: {stats['errors']}")

        if orphan_stats:
            print()
            print("Orphan Cleanup:")
            print(f"  Found: {orphan_stats['found']}")
            print(f"  Deleted: {orphan_stats['deleted']}")
            print(f"  Errors: {orphan_stats['errors']}")

        print("=" * 60)

    except KeyboardInterrupt:
        print("\n\nInterrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\nError: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
