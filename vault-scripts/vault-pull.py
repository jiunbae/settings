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
from datetime import datetime
from pathlib import Path
from typing import Optional
from concurrent.futures import ThreadPoolExecutor, as_completed

# ============================================================================
# Configuration
# ============================================================================

VAULT_ROOT = Path.home() / "s-lastorder"

# CouchDB 설정 (환경변수 또는 기본값)
COUCHDB_URI = os.environ.get("COUCHDB_URI", "https://your-couchdb-server")
COUCHDB_USER = os.environ.get("COUCHDB_USER", "admin")
COUCHDB_PASSWORD = os.environ.get("COUCHDB_PASSWORD", "")
COUCHDB_DB = os.environ.get("COUCHDB_DB", "obsidian")

if not COUCHDB_PASSWORD:
    print("Error: COUCHDB_PASSWORD environment variable is required", file=sys.stderr)
    print("Set it with: export COUCHDB_PASSWORD='your-password'", file=sys.stderr)
    sys.exit(1)

# 동시 요청 수
MAX_WORKERS = 10

# 제외 패턴
EXCLUDE_PATTERNS = [
    ".obsidian/",
    ".git/",
    ".DS_Store",
    "node_modules/",
]


def couchdb_request(path: str, method: str = "GET", data: dict = None) -> dict:
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
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return None
        raise


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
        start_key = urllib.request.quote(f'"{path_filter}"')
        end_key = urllib.request.quote(f'"{path_filter}\ufff0"')
        queries = [f"_all_docs?include_docs=true&startkey={start_key}&endkey={end_key}"]
    else:
        # 청크(h:)를 제외하기 위해 두 범위로 나눔:
        # 1. 처음 ~ h: 이전 (!, ", #, $, ... g, gz 등)
        # 2. h; 이후 ~ 끝 (i, j, k, ... z, 한글 등)
        queries = [
            '_all_docs?include_docs=true&endkey=%22h:%22',  # 처음 ~ h: 이전
            '_all_docs?include_docs=true&startkey=%22i%22',  # i 이후 ~ 끝
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

            # children이 있는 문서만 (파일 문서)
            if 'children' in doc:
                documents.append(doc)

    return documents


def get_chunk(chunk_id: str) -> Optional[str]:
    """청크 데이터 가져오기"""
    try:
        chunk_url = urllib.request.quote(chunk_id, safe='')
        chunk_doc = couchdb_request(chunk_url)
        if chunk_doc:
            return chunk_doc.get('data', '')
    except Exception as e:
        print(f"  Warning: Failed to get chunk {chunk_id}: {e}", file=sys.stderr)
    return None


def get_document_content(doc: dict) -> Optional[str]:
    """문서의 전체 내용 조합"""
    children = doc.get('children', [])
    if not children:
        return ""

    # 병렬로 청크 가져오기
    chunks = {}
    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        future_to_idx = {
            executor.submit(get_chunk, chunk_id): idx
            for idx, chunk_id in enumerate(children)
        }

        for future in as_completed(future_to_idx):
            idx = future_to_idx[future]
            try:
                chunk_data = future.result()
                if chunk_data is not None:
                    chunks[idx] = chunk_data
            except Exception as e:
                print(f"  Warning: Chunk fetch error: {e}", file=sys.stderr)

    # 순서대로 조합
    content_parts = []
    for idx in range(len(children)):
        if idx in chunks:
            content_parts.append(chunks[idx])
        else:
            print(f"  Warning: Missing chunk at index {idx}", file=sys.stderr)

    return ''.join(content_parts)


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
    """CouchDB에서 문서 pull"""

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

    print()

    for doc in documents:
        doc_id = doc.get('_id', '')
        doc_path = doc.get('path', doc_id)

        # 경로 정리 (앞의 / 제거)
        if doc_path.startswith('/'):
            doc_path = doc_path[1:]

        # 제외 패턴 확인
        if should_exclude(doc_path):
            if verbose:
                print(f"  [SKIP] {doc_path} (excluded)")
            stats['skipped'] += 1
            continue

        local_path = VAULT_ROOT / doc_path

        # mtime 확인 (changed_only 모드)
        if changed_only and local_path.exists():
            local_mtime = datetime.fromtimestamp(local_path.stat().st_mtime)
            remote_mtime_str = doc.get('mtime', '')

            if remote_mtime_str:
                try:
                    # ISO 형식 또는 timestamp
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
                    pass  # mtime 파싱 실패시 무시하고 진행

        # 문서 내용 가져오기
        try:
            content = get_document_content(doc)
            if content is None:
                print(f"  [ERROR] {doc_path} (failed to get content)")
                stats['errors'] += 1
                continue
        except Exception as e:
            print(f"  [ERROR] {doc_path}: {e}")
            stats['errors'] += 1
            continue

        # 파일 쓰기
        action = "UPDATE" if local_path.exists() else "CREATE"

        if dry_run:
            print(f"  [{action}] {doc_path} ({len(content)} chars)")
        else:
            try:
                local_path.parent.mkdir(parents=True, exist_ok=True)
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
                    print(f"  [{action}] {doc_path} ({len(content)} chars)")
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

    args = parser.parse_args()

    print("=" * 60)
    print("Obsidian Vault Pull")
    print("=" * 60)

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
