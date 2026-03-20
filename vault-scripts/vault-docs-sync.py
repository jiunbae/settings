#!/usr/bin/env python3
"""
Vault Docs Sync - Obsidian vault의 publish: true 문서를 docs 서버에 동기화

articles/*.md 에서 frontmatter의 publish: true인 파일만 docs.jiun.dev에
rsync하고, 서버에서 제거된 파일은 삭제합니다.

사용법:
    python vault-docs-sync.py              # 변경된 파일만 동기화
    python vault-docs-sync.py --force      # 전부 강제 동기화
    python vault-docs-sync.py --dry-run    # 미리보기
    python vault-docs-sync.py -v           # 상세 출력
"""

import argparse
import os
import re
import shlex
import subprocess
import sys
import tempfile
import shutil
from pathlib import Path

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR = Path(__file__).resolve().parent
VAULT_ROOT = Path.home() / "s-lastorder"
ARTICLES_DIR = VAULT_ROOT / "articles"

# Files to exclude from sync
EXCLUDE_FILES = {"INDEX.md", "_sidebar.md", "README.md", "index.md"}

# Valid filename pattern for remote operations
_SAFE_FILENAME_RE = re.compile(r'^[a-zA-Z0-9가-힣._\- ]+\.md$')
# Valid DOCS_ROOT pattern
_SAFE_PATH_RE = re.compile(r'^/[a-zA-Z0-9/_.\-]+$')


def _load_env_files() -> None:
    """환경변수 파일 로드"""
    for env_path in [
        Path.home() / ".envs" / "docs-publish.env",
        SCRIPT_DIR / ".env",
    ]:
        if not env_path.exists():
            continue
        for line in env_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("export "):
                line = line[7:]
            if "=" not in line:
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            value = value.strip().strip("'\"")
            if key not in os.environ:
                os.environ[key] = value


_load_env_files()

DOCS_HOST = os.environ.get("DOCS_HOST", "192.168.32.70")
DOCS_USER = os.environ.get("DOCS_USER", "root")
DOCS_ROOT = os.environ.get("DOCS_ROOT", "/var/www/docs")
DOCS_URL = os.environ.get("DOCS_URL", "https://docs.jiun.dev")


def _validate_config() -> None:
    """설정값 검증"""
    if not _SAFE_PATH_RE.match(DOCS_ROOT):
        print(f"Error: DOCS_ROOT contains invalid characters: {DOCS_ROOT}", file=sys.stderr)
        sys.exit(1)


# ============================================================================
# Frontmatter Parsing
# ============================================================================

def parse_publish_flag(filepath: Path) -> bool:
    """frontmatter에서 publish: true 여부 확인 (첫 4KB만 읽음)"""
    try:
        with open(filepath, encoding="utf-8", errors="replace") as f:
            header = f.read(4096)
    except Exception:
        return False

    if not header.startswith("---"):
        return False

    end = header.find("---", 3)
    if end < 0:
        return False

    frontmatter = header[3:end]
    return bool(re.search(r'^publish:\s*true\s*$', frontmatter, re.MULTILINE))


def scan_publishable_articles() -> list[Path]:
    """publish: true인 articles 목록 반환"""
    if not ARTICLES_DIR.exists():
        return []

    publishable = []
    for f in sorted(ARTICLES_DIR.iterdir()):
        if not f.is_file() or f.suffix != ".md":
            continue
        if f.name in EXCLUDE_FILES:
            continue
        if parse_publish_flag(f):
            publishable.append(f)

    return publishable


# ============================================================================
# Remote Operations
# ============================================================================

def _ssh_cmd(command: str) -> subprocess.CompletedProcess:
    """SSH 명령 실행 (DOCS_ROOT는 이미 검증됨)"""
    return subprocess.run(
        ["ssh", f"{DOCS_USER}@{DOCS_HOST}", command],
        capture_output=True, text=True, timeout=15,
    )


def get_remote_files() -> set[str]:
    """docs 서버의 현재 파일 목록"""
    try:
        result = _ssh_cmd(
            f"find {shlex.quote(DOCS_ROOT)} -maxdepth 1 -name '*.md' "
            f"-not -name '_sidebar.md' -not -name 'README.md' "
            f"-not -name 'index.md' -printf '%f\\n'"
        )
        if result.returncode != 0:
            print(f"  [WARN] Failed to list remote files: {result.stderr.strip()}")
            return set()
        return {f.strip() for f in result.stdout.splitlines() if f.strip()}
    except Exception as e:
        print(f"  [WARN] SSH error: {e}")
        return set()


def rsync_files(files: list[Path], dry_run: bool = False) -> int:
    """파일들을 docs 서버에 rsync"""
    if not files:
        return 0

    with tempfile.TemporaryDirectory() as tmpdir:
        for f in files:
            shutil.copy2(f, os.path.join(tmpdir, f.name))

        cmd = [
            "rsync", "-rltz", "--checksum",
            "--include=*.md",
            "--include=*.png", "--include=*.jpg",
            "--include=*.jpeg", "--include=*.gif", "--include=*.svg",
            "--exclude=*",
        ]
        if dry_run:
            cmd.extend(["--dry-run", "-v"])

        cmd.extend([
            f"{tmpdir}/",
            f"{DOCS_USER}@{DOCS_HOST}:{DOCS_ROOT}/",
        ])

        result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        if result.returncode != 0:
            print(f"  [ERROR] rsync failed: {result.stderr.strip()}")
            return -1

        if dry_run and result.stdout.strip():
            for line in result.stdout.strip().splitlines():
                if line.endswith(".md"):
                    print(f"  [SYNC] {line}")

    # Fix permissions after rsync (macOS openrsync doesn't support --chmod/--chown)
    if not dry_run:
        try:
            _ssh_cmd(
                f"chmod 755 {shlex.quote(DOCS_ROOT)} && "
                f"find {shlex.quote(DOCS_ROOT)} -maxdepth 1 -type f -exec chmod 644 {{}} + && "
                f"chown -R www-data:www-data {shlex.quote(DOCS_ROOT)}"
            )
        except Exception as e:
            print(f"  [WARN] Permission fix failed: {e}")

    return len(files)


def delete_remote_files(files: set[str], dry_run: bool = False) -> int:
    """docs 서버에서 파일 삭제 (일괄 처리)"""
    if not files:
        return 0

    # Validate all filenames before executing
    safe_files = []
    for f in sorted(files):
        if not _SAFE_FILENAME_RE.match(f):
            print(f"  [WARN] Skipping unsafe filename: {f}")
            continue
        safe_files.append(f)

    if dry_run:
        for f in safe_files:
            print(f"  [DELETE] {f}")
        return len(safe_files)

    if safe_files:
        # Batch delete in single SSH call
        rm_args = " ".join(
            shlex.quote(f"{DOCS_ROOT}/{f}") for f in safe_files
        )
        try:
            _ssh_cmd(f"rm -f {rm_args}")
        except Exception as e:
            print(f"  [ERROR] Batch delete failed: {e}")

    return len(safe_files)


def trigger_sidebar_update() -> None:
    """서버의 sidebar 재생성 트리거"""
    try:
        _ssh_cmd("/usr/local/bin/update-sidebar")
    except Exception:
        pass


# ============================================================================
# Main Sync Logic
# ============================================================================

def sync(force: bool = False, dry_run: bool = False, verbose: bool = False) -> dict:
    stats = {"synced": 0, "deleted": 0, "skipped": 0, "errors": 0}

    # 1. Scan publishable articles
    print("[Scan] Checking articles for publish: true...")
    publishable = scan_publishable_articles()
    local_names = {f.name for f in publishable}
    print(f"  Publishable: {len(publishable)} articles")

    if verbose:
        for f in publishable:
            print(f"    {f.name}")

    # 2. Get remote file list
    print("[Remote] Checking docs server...")
    remote_names = get_remote_files()
    print(f"  Published: {len(remote_names)} articles")

    # 3. Determine what to sync
    # rsync --checksum handles deduplication, so always pass all publishable files
    to_sync = publishable
    to_delete = remote_names - local_names

    new_files = local_names - remote_names
    if new_files:
        print(f"  New: {len(new_files)} articles")
        if verbose:
            for f in sorted(new_files):
                print(f"    + {f}")

    if to_delete:
        print(f"  To remove: {len(to_delete)} articles (no longer publish: true)")
        if verbose:
            for f in sorted(to_delete):
                print(f"    - {f}")

    # 4. Sync
    if to_sync:
        action = "DRY RUN" if dry_run else "Sync"
        print(f"\n[{action}] Pushing {len(to_sync)} articles to {DOCS_HOST}...")
        result = rsync_files(to_sync, dry_run=dry_run)
        if result >= 0:
            stats["synced"] = result
        else:
            stats["errors"] += 1

    # 5. Delete unpublished files from server
    if to_delete:
        action = "DRY RUN" if dry_run else "Delete"
        print(f"[{action}] Removing {len(to_delete)} unpublished articles...")
        stats["deleted"] = delete_remote_files(to_delete, dry_run=dry_run)

    # 6. Trigger sidebar update
    if not dry_run and (to_sync or to_delete):
        print("[Sidebar] Regenerating sidebar...")
        trigger_sidebar_update()

    stats["skipped"] = max(0, len(remote_names) - len(to_delete) - len(new_files))

    return stats


def main():
    parser = argparse.ArgumentParser(
        description="Sync publish:true articles from Obsidian vault to docs server"
    )
    parser.add_argument("--dry-run", action="store_true", help="Preview without changes")
    parser.add_argument("--force", action="store_true", help="Force sync all files")
    parser.add_argument("-v", "--verbose", action="store_true", help="Verbose output")

    args = parser.parse_args()

    print("=" * 60)
    print(f"Vault Docs Sync → {DOCS_URL}")
    print("=" * 60)

    _validate_config()

    if args.dry_run:
        print("[DRY RUN] No changes will be made\n")

    try:
        stats = sync(force=args.force, dry_run=args.dry_run, verbose=args.verbose)

        print()
        print("=" * 60)
        print("Summary:")
        print(f"  Synced:   {stats['synced']}")
        print(f"  Deleted:  {stats['deleted']}")
        print(f"  Errors:   {stats['errors']}")
        print("=" * 60)

    except KeyboardInterrupt:
        print("\n\nInterrupted")
        sys.exit(1)
    except Exception as e:
        print(f"\nError: {e}")
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
