# Obsidian Vault Scripts

Obsidian vault 관리 자동화 스크립트입니다.

## 설치

```bash
# Python 3.10+ 및 xxhash 필요
pip install xxhash  # vault-push.py에 필요

# 실행 권한 부여
chmod +x vault-pull.py vault-push.py vault-service.sh vault-sync-machines.sh docs-push

# CouchDB 비밀번호 설정
echo "COUCHDB_PASSWORD=your-password" > .env
```

---

## 스크립트 목록

### 동기화 스크립트

| 스크립트 | 용도 |
|---------|------|
| `vault-pull.py` | CouchDB에서 문서 가져오기 (pull) |
| `vault-push.py` | 로컬 파일을 CouchDB에 업로드 (push) |
| `claude-context-push.py` | Claude Code 세션/메모리를 CouchDB로 푸시 |
| `codex-context-push.py` | Codex CLI 세션(`~/.codex/history.jsonl`)을 CouchDB로 푸시 |
| `opencode-context-push.py` | OpenCode 세션(SQLite)을 CouchDB로 푸시 |
| `vault-docs-sync.py` | `publish: true` 문서를 docs 서버로 rsync |

### 도구 / 라이브러리

| 스크립트 | 용도 |
|---------|------|
| `vault-service.sh` | launchd 서비스 관리 (6개 서비스 등록/상태/로그) |
| `vault-sync-machines.sh` | rsync로 머신 간 vault 동기화 |
| `docs-push` | 마크다운을 docs 서버에 수동 발행 (목록/삭제/열기) |
| `couchdb_client.py` | push 계열이 공용으로 쓰는 CouchDB API 모듈 |
| `livesync_compat.py` | LiveSync 호환 청킹 라이브러리 (xxhash64 + Rabin-Karp) |

## 동기화 아키텍처

```
                  ┌─────────────────────────┐
                  │      CouchDB Server     │
                  └─────────────────────────┘
                      ▲                  │
        vault-push.py │                  │ vault-pull.py
                      │                  ▼
┌──────────────────────┐        ┌──────────────────────┐
│  Obsidian GUI Apps   │◄──────►│   Local Vault Files  │
│  (LiveSync Plugin)   │        │    ~/s-lastorder/    │
└──────────────────────┘        └───────────┬──────────┘
            ▲                               │
            │                  ┌────────────┴────────────┐
            │                  │                         │
            │      vault-sync-machines.sh      vault-docs-sync.py
            │                  │                         │
            │                  ▼                         ▼
┌───────────┴────────────┐  ┌───────────────┐  ┌───────────────────┐
│ ~/.claude/projects/    │  │  Other Macs   │  │    docs server    │
│ ~/.codex/history.jsonl │  │  (via rsync)  │  │  (docs.jiun.dev)  │
│ OpenCode SQLite        │  └───────────────┘  └───────────────────┘
└────────────────────────┘
      *-context-push.py
```

**Headless 환경 (Mac mini 등):**
- Obsidian GUI 없이 `vault-push.py` + `vault-pull.py`로 양방향 동기화
- `vault-service.sh install`로 자동 실행 (동기화 10분, context push 30분 주기)

---

## 1. vault-pull.py (Pull)

CouchDB에서 문서를 직접 가져옵니다. 표준 라이브러리만 사용 (크로스 플랫폼).

```bash
python3 vault-pull.py                      # 전체 pull
python3 vault-pull.py --changed-only       # 변경된 파일만
python3 vault-pull.py --path articles/     # 특정 경로만
python3 vault-pull.py --delete-orphans     # CouchDB에 없는 파일 삭제
python3 vault-pull.py --dry-run            # 미리보기
python3 vault-pull.py -v                   # 상세 출력
```

---

## 2. vault-push.py (Push)

로컬 파일을 LiveSync 호환 형식으로 CouchDB에 업로드합니다. `xxhash` 패키지 필요.

```bash
python3 vault-push.py                      # 변경된 파일만 push
python3 vault-push.py --force              # 모든 파일 강제 push
python3 vault-push.py --path articles/     # 특정 경로만
python3 vault-push.py --verify             # 청크 ID 검증 (CouchDB와 비교)
python3 vault-push.py --dry-run            # 미리보기
python3 vault-push.py -v                   # 상세 출력
```

---

## 3. claude-context-push.py (Claude Context Push)

`~/.claude/projects/`의 세션 메타데이터와 메모리 파일을 Obsidian CouchDB로 푸시합니다.

**푸시 대상:**
- `sessions-index.json` → 세션별 마크다운 요약 (`claude-context/sessions/`)
- `memory/` → 메모리 파일 그대로 (`claude-context/memory/`)
- `CLAUDE.md` → 프로젝트 설정 파일 (`claude-context/CLAUDE.md`)
- 프로젝트 인덱스 (`claude-context/INDEX.md`)

**스캔 대상:** `~/workspace/*/`, `~/workspace-ext/*/`, `~/workspace-vibe/*/` 등 모든 workspace 변형

```bash
python3 claude-context-push.py                    # 변경된 파일만 push
python3 claude-context-push.py --force            # 모든 파일 강제 push
python3 claude-context-push.py --project settings # 특정 프로젝트만
python3 claude-context-push.py --dry-run          # 미리보기
python3 claude-context-push.py -v                 # 상세 출력
```

---

## 4. codex / opencode context push

Claude Code 외 다른 CLI 에이전트의 세션도 같은 방식으로 푸시합니다.

```bash
python3 codex-context-push.py       # ~/.codex/history.jsonl 에서 변환
python3 opencode-context-push.py    # OpenCode SQLite DB에서 변환
```

둘 다 `--force` / `--dry-run` / `-v`를 지원하며, `opencode-context-push.py`는
`--project NAME`으로 특정 프로젝트만 처리할 수 있습니다.

---

## 5. vault-docs-sync.py / docs-push (문서 발행)

`vault-docs-sync.py`는 `articles/*.md`의 frontmatter가 `publish: true`인 파일만
docs 서버로 rsync하고, 서버에서 제거된 파일은 삭제합니다. launchd로 자동 실행됩니다.

```bash
python3 vault-docs-sync.py            # 변경분만 동기화
python3 vault-docs-sync.py --force    # 전부 강제 동기화
python3 vault-docs-sync.py --dry-run  # 미리보기
```

`docs-push`는 vault를 거치지 않고 임의의 마크다운을 수동 발행하는 도구입니다.
설정은 `~/.envs/docs-publish.env`에서 읽습니다.

```bash
docs-push ./article.md            # 단일 파일 발행
docs-push ./folder/               # 디렉토리 전체 발행
docs-push --list                  # 발행된 문서 목록
docs-push --delete article.md     # 발행 취소
docs-push --open article          # 브라우저로 열기
```

---

## 6. vault-service.sh (서비스 관리)

macOS launchd 서비스 관리. 6개 서비스가 등록되어 있습니다.

| 이름 | 스크립트 | 주기 |
|------|---------|------|
| `pull` | `vault-pull.py --changed-only` | 10분 |
| `push` | `vault-push.py` | 10분 |
| `docs` | `vault-docs-sync.py` | 10분 |
| `context` | `claude-context-push.py` | 30분 |
| `codex` | `codex-context-push.py` | 30분 |
| `opencode` | `opencode-context-push.py` | 30분 |

```bash
./vault-service.sh install          # launchd plist 설치 및 서비스 시작
./vault-service.sh status           # 서비스 상태 확인
./vault-service.sh restart [name]   # 서비스 재시작 (생략 시 전체)
./vault-service.sh stop [name]      # 서비스 중지
./vault-service.sh logs [name]      # 최근 로그 확인
```

로그는 `~/Library/Logs/vault-scripts/`(권한 700)에 기록됩니다.
`VAULT_LOG_DIR`로 위치를 바꿀 수 있습니다.

---

## 7. vault-sync-machines.sh (머신 간 동기화)

rsync를 사용하여 SSH로 다른 Mac에 vault 동기화.

```bash
./vault-sync-machines.sh                   # 모든 머신에 동기화
./vault-sync-machines.sh june-mbp          # 특정 머신만
./vault-sync-machines.sh --dry-run         # 미리보기
```

---

## 환경변수

CouchDB 접속 정보는 `.env` 파일 또는 환경변수로 설정합니다:

```bash
COUCHDB_PASSWORD=your-password           # 필수
COUCHDB_URI=https://your-couchdb-server  # 필수
COUCHDB_USER=admin                       # 기본값
COUCHDB_DB=obsidian                      # 기본값
VAULT_LOG_DIR=~/Library/Logs/vault-scripts  # 기본값
```

`docs-push`는 별도로 `~/.envs/docs-publish.env`에서 읽습니다:

```bash
DOCS_HOST=192.168.32.70          # 기본값
DOCS_USER=root                   # 기본값
DOCS_ROOT=/var/www/docs          # 기본값
DOCS_URL=https://docs.jiun.dev   # 기본값
```

## 동기화 대상 디렉토리

| Vault 경로 | 설명 |
|-----------|------|
| `workspace/{project}/` | 프로젝트 워크스페이스 |
| `workspace-vibe/{service}/` | Vibe 서비스 |
| `workspace-ext/{project}/` | 외부 프로젝트 |
| `articles/` | 아티클 |
| `Notes/` | 노트 |
| `TaskManager/` | 태스크 관리 |
