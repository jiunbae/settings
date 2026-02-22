#!/usr/bin/env python3
"""
Obsidian Vault Push - 로컬 파일을 CouchDB로 푸시

Obsidian LiveSync 호환 형식으로 로컬 vault 파일을 CouchDB에 업로드합니다.
LiveSync와 동일한 xxhash64 + Rabin-Karp 청킹을 사용합니다.

사용법:
    # 변경된 파일만 푸시
    python vault-push.py

    # 미리보기
    python vault-push.py --dry-run

    # 모든 파일 강제 푸시
    python vault-push.py --force

    # 특정 경로만
    python vault-push.py --path articles/

    # 청크 ID 검증 (CouchDB와 비교)
    python vault-push.py --verify

    # 상세 출력
    python vault-push.py --verbose
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
from concurrent.futures import ThreadPoolExecutor, as_completed

import livesync_compat

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

COUCHDB_URI = os.environ.get("COUCHDB_URI", "https://obsidian.jiun.dev")
COUCHDB_USER = os.environ.get("COUCHDB_USER", "admin")
COUCHDB_PASSWORD = os.environ.get("COUCHDB_PASSWORD", "")
COUCHDB_DB = os.environ.get("COUCHDB_DB", "obsidian")

MAX_WORKERS = 10

# 동기화 대상 디렉토리
SYNC_DIRECTORIES = [
    "workspace",
    "workspace-vibe",
    "workspace-ext",
    "articles",
    "Notes",
    "TaskManager",
]

EXCLUDE_PATTERNS = [
    ".obsidian/",
    ".git/",
    ".DS_Store",
    "node_modules/",
]


def validate_config() -> None:
    if not COUCHDB_PASSWORD:
        env_path = SCRIPT_DIR / ".env"
        print("Error: COUCHDB_PASSWORD is required", file=sys.stderr)
        print(f"\nCreate {env_path} with:", file=sys.stderr)
        print("  COUCHDB_PASSWORD=your-password", file=sys.stderr)
        sys.exit(1)


# ============================================================================
# CouchDB API
# ============================================================================

def couchdb_request(
    path: str,
    method: str = "GET",
    data: dict = None,
    timeout: int = 30
) -> Optional[dict]:
    """CouchDB API 요청"""
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
    req.add_header('User-Agent', 'vault-push/1.0')

    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        if e.code == 409:
            # Conflict - document was updated externally
            return {"error": "conflict", "reason": "Document update conflict"}
        raw = ""
        try:
            raw = e.read().decode("utf-8", errors="replace").strip()
        except Exception:
            pass
        raise RuntimeError(f"HTTP {e.code}: {e.reason} ({url})\n{raw[:500]}") from e


def couchdb_head(path: str) -> bool:
    """Check if document exists (HEAD request)"""
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
    """Get current _rev for a document"""
    encoded_id = urllib.parse.quote(doc_id, safe='')
    doc = couchdb_request(encoded_id)
    if doc and '_rev' in doc:
        return doc['_rev']
    return None


def put_document(doc: dict) -> dict:
    """PUT a document to CouchDB"""
    doc_id = doc['_id']
    encoded_id = urllib.parse.quote(doc_id, safe='')
    return couchdb_request(encoded_id, method="PUT", data=doc)


# ============================================================================
# Local File Scanning
# ============================================================================

def should_exclude(path: str) -> bool:
    """제외 패턴 확인"""
    for pattern in EXCLUDE_PATTERNS:
        if pattern in path:
            return True
    return False


def get_local_files(path_filter: Optional[str] = None) -> list[dict]:
    """로컬 vault 파일 스캔"""
    files = []

    for sync_dir in SYNC_DIRECTORIES:
        dir_path = VAULT_ROOT / sync_dir
        if not dir_path.exists():
            continue

        if path_filter and not sync_dir.startswith(path_filter.split('/')[0]):
            continue

        for file_path in dir_path.rglob('*'):
            if not file_path.is_file():
                continue

            rel_path = str(file_path.relative_to(VAULT_ROOT))

            if should_exclude(rel_path):
                continue

            if path_filter and not rel_path.startswith(path_filter):
                continue

            stat = file_path.stat()
            files.append({
                'path': rel_path,
                'abs_path': file_path,
                'mtime': int(stat.st_mtime * 1000),  # ms
                'ctime': int(stat.st_ctime * 1000),  # ms
                'size': stat.st_size,
            })

    return files


# ============================================================================
# Remote Document Fetching (for change detection)
# ============================================================================

def get_remote_documents() -> dict[str, dict]:
    """
    CouchDB에서 모든 파일 문서의 메타데이터 가져오기 (청크 제외)

    Returns: {path: {_id, _rev, mtime, children, ...}}
    """
    documents = {}

    # 청크(h:)를 제외하기 위해 두 범위로 나눔 (vault-pull.py와 동일)
    end_key = urllib.parse.quote(json.dumps("h:"), safe='')
    start_key = urllib.parse.quote(json.dumps("h;"), safe='')
    queries = [
        f'_all_docs?include_docs=true&endkey={end_key}',
        f'_all_docs?include_docs=true&startkey={start_key}',
    ]

    for query in queries:
        result = couchdb_request(query)
        if not result:
            continue

        for row in result.get('rows', []):
            doc = row.get('doc', {})
            doc_id = doc.get('_id', '')

            if doc_id.startswith('h:') or doc_id.startswith('_'):
                continue

            if 'children' in doc or 'data' in doc:
                path = doc.get('path', doc_id)
                if path.startswith('/'):
                    path = path[1:]
                documents[path] = doc

    return documents


# ============================================================================
# Push Logic
# ============================================================================

def upload_chunk(chunk_id: str, chunk_data: str) -> bool:
    """Upload a single chunk to CouchDB"""
    encoded_id = urllib.parse.quote(chunk_id, safe='')

    # Check if chunk already exists
    if couchdb_head(encoded_id):
        return True  # Already exists, deduplication

    doc = {
        "_id": chunk_id,
        "data": chunk_data,
        "type": "leaf",
    }

    result = put_document(doc)
    if result and result.get("error") == "conflict":
        return True  # Another process uploaded it
    return result is not None and result.get("ok", False)


def push_file(
    file_info: dict,
    remote_doc: Optional[dict] = None,
    dry_run: bool = False,
    verbose: bool = False
) -> Optional[str]:
    """
    Push a single file to CouchDB.

    Returns: "created", "updated", "skipped", or "error"
    """
    rel_path = file_info['path']
    abs_path = file_info['abs_path']

    try:
        content = abs_path.read_text(encoding='utf-8')
    except Exception as e:
        print(f"  [ERROR] {rel_path}: {e}")
        return "error"

    # Chunk the content
    chunk_ids, chunks = livesync_compat.process_document(content)

    if dry_run:
        action = "UPDATE" if remote_doc else "CREATE"
        print(f"  [{action}] {rel_path} ({len(chunks)} chunks, {file_info['size']} bytes)")
        return "created" if not remote_doc else "updated"

    # Upload chunks in parallel
    failed_chunks = []
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        future_to_idx = {
            executor.submit(upload_chunk, cid, cdata): (cid, idx)
            for idx, (cid, cdata) in enumerate(zip(chunk_ids, chunks))
        }

        for future in as_completed(future_to_idx):
            cid, idx = future_to_idx[future]
            try:
                if not future.result():
                    failed_chunks.append(cid)
            except Exception as e:
                print(f"  [WARN] Chunk upload failed {cid}: {e}")
                failed_chunks.append(cid)

    if failed_chunks:
        print(f"  [ERROR] {rel_path}: {len(failed_chunks)} chunks failed to upload")
        return "error"

    # Build file document
    file_doc = {
        "_id": rel_path,
        "path": rel_path,
        "children": chunk_ids,
        "ctime": file_info['ctime'],
        "mtime": file_info['mtime'],
        "size": file_info['size'],
        "type": "plain",
    }

    # Get _rev if document already exists
    if remote_doc and '_rev' in remote_doc:
        file_doc['_rev'] = remote_doc['_rev']
    elif not remote_doc:
        # Double-check: might exist but wasn't in our batch
        existing_rev = get_document_rev(rel_path)
        if existing_rev:
            file_doc['_rev'] = existing_rev

    result = put_document(file_doc)

    if result and result.get("error") == "conflict":
        # Retry with fresh _rev
        rev = get_document_rev(rel_path)
        if rev:
            file_doc['_rev'] = rev
            result = put_document(file_doc)

    if result is None or result.get("error"):
        err_msg = result.get("reason", "unknown") if result else "no response"
        print(f"  [ERROR] {rel_path}: {err_msg}")
        return "error"

    action = "UPDATE" if remote_doc else "CREATE"
    if verbose:
        print(f"  [{action}] {rel_path} ({len(chunks)} chunks)")

    return "created" if not remote_doc else "updated"


def push_documents(
    path_filter: Optional[str] = None,
    force: bool = False,
    dry_run: bool = False,
    verbose: bool = False,
) -> dict:
    """Push local files to CouchDB"""

    stats = {
        'total': 0,
        'created': 0,
        'updated': 0,
        'skipped': 0,
        'errors': 0,
    }

    print(f"\n[Push] Scanning local files...")
    local_files = get_local_files(path_filter=path_filter)
    stats['total'] = len(local_files)
    print(f"  Local files: {len(local_files)}")

    if not local_files:
        print("  No files to push.")
        return stats

    print(f"\n[Push] Fetching remote document metadata...")
    remote_docs = get_remote_documents()
    print(f"  Remote documents: {len(remote_docs)}")
    print()

    for file_info in local_files:
        rel_path = file_info['path']
        remote_doc = remote_docs.get(rel_path)

        # Change detection (skip if remote mtime >= local mtime)
        if not force and remote_doc:
            remote_mtime = remote_doc.get('mtime', 0)
            if isinstance(remote_mtime, str):
                try:
                    if 'T' in remote_mtime:
                        remote_mtime = int(
                            datetime.fromisoformat(
                                remote_mtime.replace('Z', '+00:00')
                            ).timestamp() * 1000
                        )
                    else:
                        remote_mtime = int(remote_mtime)
                except (ValueError, TypeError):
                    remote_mtime = 0

            if remote_mtime >= file_info['mtime']:
                if verbose:
                    print(f"  [SKIP] {rel_path} (not changed)")
                stats['skipped'] += 1
                continue

        result = push_file(
            file_info,
            remote_doc=remote_doc,
            dry_run=dry_run,
            verbose=verbose,
        )

        if result == "created":
            stats['created'] += 1
        elif result == "updated":
            stats['updated'] += 1
        elif result == "error":
            stats['errors'] += 1
        else:
            stats['skipped'] += 1

    return stats


# ============================================================================
# Verify Mode
# ============================================================================

def verify_chunks(
    path_filter: Optional[str] = None,
    verbose: bool = False,
) -> None:
    """
    검증 모드: 로컬 파일을 청킹한 결과와 CouchDB의 children 배열 비교.
    알고리즘이 LiveSync와 호환되는지 확인.
    """
    print(f"\n[Verify] Fetching remote documents...")
    remote_docs = get_remote_documents()

    # Pick sample documents (up to 10)
    samples = []
    for path, doc in remote_docs.items():
        if 'children' not in doc or not doc['children']:
            continue
        local_path = VAULT_ROOT / path
        if not local_path.exists():
            continue
        if path_filter and not path.startswith(path_filter):
            continue
        samples.append((path, doc))
        if len(samples) >= 10:
            break

    if not samples:
        print("  No matching documents found for verification.")
        return

    print(f"  Verifying {len(samples)} documents...\n")

    match_count = 0
    mismatch_count = 0

    for path, remote_doc in samples:
        local_path = VAULT_ROOT / path
        try:
            content = local_path.read_text(encoding='utf-8')
        except Exception as e:
            print(f"  [ERROR] {path}: {e}")
            continue

        local_chunk_ids, local_chunks = livesync_compat.process_document(content)
        remote_children = remote_doc.get('children', [])

        if local_chunk_ids == remote_children:
            match_count += 1
            if verbose:
                print(f"  [MATCH] {path} ({len(local_chunk_ids)} chunks)")
        else:
            mismatch_count += 1
            print(f"  [MISMATCH] {path}")
            print(f"    Local:  {len(local_chunk_ids)} chunks")
            print(f"    Remote: {len(remote_children)} chunks")
            if verbose:
                # Show first differing chunk
                for i, (l, r) in enumerate(
                    zip(local_chunk_ids, remote_children)
                ):
                    if l != r:
                        print(f"    First diff at chunk {i}: local={l} remote={r}")
                        break

    print(f"\n  Results: {match_count} match, {mismatch_count} mismatch")
    if mismatch_count == 0:
        print("  Chunking algorithm is compatible with LiveSync!")
    else:
        print("  WARNING: Chunking mismatch detected. "
              "Push may create duplicate chunks in CouchDB.")
        print("  This is not destructive - LiveSync will normalize on next sync.")


# ============================================================================
# Main
# ============================================================================

def main():
    parser = argparse.ArgumentParser(description="Push local vault files to CouchDB")
    parser.add_argument('--dry-run', action='store_true', help='Preview without uploading')
    parser.add_argument('--force', action='store_true', help='Push all files regardless of mtime')
    parser.add_argument('--path', type=str, help='Filter by path prefix')
    parser.add_argument('--verify', action='store_true', help='Verify chunk IDs against CouchDB')
    parser.add_argument('-v', '--verbose', action='store_true', help='Verbose output')

    args = parser.parse_args()

    print("=" * 60)
    print("Obsidian Vault Push")
    print("=" * 60)

    validate_config()

    if args.verify:
        verify_chunks(path_filter=args.path, verbose=args.verbose)
        return

    if args.dry_run:
        print("[DRY RUN] No changes will be made")

    try:
        stats = push_documents(
            path_filter=args.path,
            force=args.force,
            dry_run=args.dry_run,
            verbose=args.verbose,
        )

        print()
        print("=" * 60)
        print("Summary:")
        print(f"  Total files: {stats['total']}")
        print(f"  Created: {stats['created']}")
        print(f"  Updated: {stats['updated']}")
        print(f"  Skipped: {stats['skipped']}")
        print(f"  Errors: {stats['errors']}")
        print("=" * 60)

    except KeyboardInterrupt:
        print("\n\nInterrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\nError: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
