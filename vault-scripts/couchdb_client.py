"""
CouchDB Client - Obsidian LiveSync 호환 CouchDB 클라이언트

vault-push, claude-context-push, codex-context-push, opencode-context-push에서
공용으로 사용하는 CouchDB API 모듈입니다.
"""

import base64
import json
import os
import sys
import urllib.request
import urllib.error
import urllib.parse
from pathlib import Path
from typing import Optional
from concurrent.futures import ThreadPoolExecutor, as_completed

import livesync_compat


# ============================================================================
# Environment & Configuration
# ============================================================================

SCRIPT_DIR = Path(__file__).resolve().parent

# Workspace variants — single source of truth
WORKSPACE_VARIANTS = [
    "workspace", "workspace-ext", "workspace-vibe",
    "workspace-game", "workspace-open330",
]


def load_env_file() -> None:
    """스크립트 디렉토리의 .env 파일에서 환경변수 로드 (export 접두사 지원)"""
    for env_path in [
        SCRIPT_DIR / ".env",
        Path.home() / ".envs" / "couchdb.env",
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


def get_couchdb_config() -> dict:
    """CouchDB 설정을 환경변수에서 로드하고 검증"""
    load_env_file()
    config = {
        "uri": os.environ.get("COUCHDB_URI", ""),
        "user": os.environ.get("COUCHDB_USER", "admin"),
        "password": os.environ.get("COUCHDB_PASSWORD", ""),
        "db": os.environ.get("COUCHDB_DB", "obsidian"),
    }

    missing = []
    if not config["uri"]:
        missing.append("COUCHDB_URI")
    if not config["password"]:
        missing.append("COUCHDB_PASSWORD")
    if missing:
        env_path = SCRIPT_DIR / ".env"
        print(f"Error: {', '.join(missing)} required", file=sys.stderr)
        print(f"\nCreate {env_path} with:", file=sys.stderr)
        print("  COUCHDB_URI=https://your-couchdb-server", file=sys.stderr)
        print("  COUCHDB_PASSWORD=your-password", file=sys.stderr)
        sys.exit(1)

    if not config["uri"].startswith("https://"):
        print("WARNING: COUCHDB_URI is not HTTPS; credentials sent in cleartext",
              file=sys.stderr)

    return config


def _redact_url(url: str) -> str:
    """URL에서 인증 정보를 제거"""
    try:
        parsed = urllib.parse.urlparse(url)
        if parsed.username or parsed.password:
            redacted = parsed._replace(
                netloc=f"***@{parsed.hostname}" + (f":{parsed.port}" if parsed.port else "")
            )
            return urllib.parse.urlunparse(redacted)
    except Exception:
        pass
    return url


# ============================================================================
# CouchDB Client
# ============================================================================

class CouchDBClient:
    """Obsidian LiveSync 호환 CouchDB 클라이언트"""

    def __init__(self, uri: str, db: str, user: str, password: str,
                 user_agent: str = "vault-scripts/1.0", max_workers: int = 10):
        self.uri = uri
        self.db = db
        self.user_agent = user_agent
        self.max_workers = max_workers
        # Pre-compute auth header (avoid recomputing per request)
        self._auth_header = base64.b64encode(
            f"{user}:{password}".encode()
        ).decode()

    def request(self, path: str, method: str = "GET",
                data: dict = None, timeout: int = 30) -> Optional[dict]:
        url = f"{self.uri}/{self.db}/{path}"
        body = json.dumps(data).encode('utf-8') if data is not None else None
        req = urllib.request.Request(url, data=body, method=method)
        req.add_header('Authorization', f'Basic {self._auth_header}')
        req.add_header('Content-Type', 'application/json')
        req.add_header('User-Agent', self.user_agent)

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
            raise RuntimeError(
                f"HTTP {e.code}: {e.reason} ({_redact_url(url)})\n{raw[:500]}"
            ) from e
        except urllib.error.URLError as e:
            raise RuntimeError(
                f"Connection error ({_redact_url(url)}): {e.reason}"
            ) from e

    def head(self, path: str) -> bool:
        url = f"{self.uri}/{self.db}/{path}"
        req = urllib.request.Request(url, method="HEAD")
        req.add_header('Authorization', f'Basic {self._auth_header}')
        try:
            with urllib.request.urlopen(req, timeout=10):
                return True
        except (urllib.error.HTTPError, urllib.error.URLError):
            return False

    def get_rev(self, doc_id: str) -> Optional[str]:
        encoded_id = urllib.parse.quote(doc_id, safe='')
        doc = self.request(encoded_id)
        if doc and '_rev' in doc:
            return doc['_rev']
        return None

    def put(self, doc: dict) -> Optional[dict]:
        doc_id = doc['_id']
        encoded_id = urllib.parse.quote(doc_id, safe='')
        return self.request(encoded_id, method="PUT", data=doc)

    def upload_chunk(self, chunk_id: str, chunk_data: str) -> bool:
        """Optimistic PUT — skip HEAD check, rely on 409 for existing chunks"""
        encoded_id = urllib.parse.quote(chunk_id, safe='')
        doc = {"_id": chunk_id, "data": chunk_data, "type": "leaf"}
        try:
            result = self.put(doc)
            if result and result.get("error") == "conflict":
                return True  # Already exists
            return result is not None and result.get("ok", False)
        except RuntimeError:
            # Check if it exists (fallback for non-409 errors)
            return self.head(encoded_id)

    def push_content(self, vault_rel_path: str, content: str, mtime_ms: int,
                     executor: ThreadPoolExecutor = None,
                     dry_run: bool = False, verbose: bool = False) -> str:
        """
        콘텐츠를 CouchDB에 LiveSync 호환 형식으로 푸시.

        Returns: "created", "updated", "skipped", "error"
        """
        chunk_ids, chunks = livesync_compat.process_document(content)
        content_bytes = len(content.encode("utf-8"))

        if dry_run:
            existing = self.get_rev(vault_rel_path)
            action = "UPDATE" if existing else "CREATE"
            print(f"  [{action}] {vault_rel_path} ({len(chunks)} chunks, {content_bytes} bytes)")
            return "created" if not existing else "updated"

        # Upload chunks (use provided executor or create temporary one)
        own_executor = executor is None
        if own_executor:
            executor = ThreadPoolExecutor(max_workers=self.max_workers)

        try:
            failed_chunks = []
            future_to_cid = {
                executor.submit(self.upload_chunk, cid, cdata): cid
                for cid, cdata in zip(chunk_ids, chunks)
            }
            for future in as_completed(future_to_cid):
                cid = future_to_cid[future]
                try:
                    if not future.result():
                        failed_chunks.append(cid)
                except Exception as e:
                    print(f"  [WARN] Chunk upload failed {cid}: {e}")
                    failed_chunks.append(cid)
        finally:
            if own_executor:
                executor.shutdown(wait=False)

        if failed_chunks:
            print(f"  [ERROR] {vault_rel_path}: {len(failed_chunks)} chunks failed")
            return "error"

        # Build file document
        file_doc = {
            "_id": vault_rel_path,
            "path": vault_rel_path,
            "children": chunk_ids,
            "ctime": mtime_ms,
            "mtime": mtime_ms,
            "size": content_bytes,
            "type": "plain",
        }

        existing_rev = self.get_rev(vault_rel_path)
        if existing_rev:
            file_doc["_rev"] = existing_rev

        result = self.put(file_doc)
        if result and result.get("error") == "conflict":
            rev = self.get_rev(vault_rel_path)
            if rev:
                file_doc["_rev"] = rev
                result = self.put(file_doc)

        if result is None or result.get("error"):
            err = result.get("reason", "unknown") if result else "no response"
            print(f"  [ERROR] {vault_rel_path}: {err}")
            return "error"

        action = "UPDATE" if existing_rev else "CREATE"
        if verbose:
            print(f"  [{action}] {vault_rel_path} ({len(chunks)} chunks)")
        return "created" if not existing_rev else "updated"


def create_client(user_agent: str = "vault-scripts/1.0") -> CouchDBClient:
    """설정을 로드하고 CouchDBClient 인스턴스 생성"""
    config = get_couchdb_config()
    return CouchDBClient(
        uri=config["uri"],
        db=config["db"],
        user=config["user"],
        password=config["password"],
        user_agent=user_agent,
    )
