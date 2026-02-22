# Obsidian Vault Scripts

Obsidian vault 관리 자동화 스크립트입니다.

## 설치

```bash
# Python 3.10+ 및 xxhash 필요
pip install xxhash  # vault-push.py에 필요

# 실행 권한 부여
chmod +x vault-pull.py vault-push.py vault-service.sh vault-sync-machines.sh

# CouchDB 비밀번호 설정
echo "COUCHDB_PASSWORD=your-password" > .env
```

---

## 스크립트 목록

| 스크립트 | 용도 |
|---------|------|
| `vault-pull.py` | CouchDB에서 문서 가져오기 (pull) |
| `vault-push.py` | 로컬 파일을 CouchDB에 업로드 (push) |
| `livesync_compat.py` | LiveSync 호환 청킹 라이브러리 (xxhash64 + Rabin-Karp) |
| `vault-service.sh` | launchd 서비스 관리 (pull/push 자동 실행) |
| `vault-sync-machines.sh` | rsync로 머신 간 vault 동기화 |

## 동기화 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                      CouchDB Server                         │
│                  (obsidian.jiun.dev)                        │
└─────────────────────────────────────────────────────────────┘
         ▲                                    │
         │ push                               │ pull
         │ (vault-push.py)                    │ (vault-pull.py)
         │                                    ▼
┌──────────────────────┐          ┌──────────────────────┐
│  Obsidian GUI Apps   │◄────────►│   Local Vault Files  │
│  (LiveSync Plugin)   │          │  ~/s-lastorder/      │
└──────────────────────┘          └──────────────────────┘
                                            │
                                  vault-sync-machines.sh
                                            │
                                    ┌───────┴───────┐
                                    │  Other Macs   │
                                    │  (via rsync)  │
                                    └───────────────┘
```

**Headless 환경 (Mac mini 등):**
- Obsidian GUI 없이 `vault-push.py` + `vault-pull.py`로 양방향 동기화
- `vault-service.sh install`로 10분마다 자동 실행

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

## 3. vault-service.sh (서비스 관리)

macOS launchd 서비스 관리. Pull/push를 10분마다 자동 실행.

```bash
./vault-service.sh install                 # launchd plist 설치 및 서비스 시작
./vault-service.sh status                  # 서비스 상태 확인
./vault-service.sh restart [pull|push]     # 서비스 재시작
./vault-service.sh stop [pull|push]        # 서비스 중지
./vault-service.sh logs [pull|push]        # 최근 로그 확인
```

---

## 4. vault-sync-machines.sh (머신 간 동기화)

rsync를 사용하여 SSH로 다른 Mac에 vault 동기화.

```bash
./vault-sync-machines.sh                   # 모든 머신에 동기화
./vault-sync-machines.sh june-mbp          # 특정 머신만
./vault-sync-machines.sh --dry-run         # 미리보기
```

---

## 환경변수

`.env` 파일 또는 환경변수로 설정:

```bash
COUCHDB_PASSWORD=your-password   # 필수
COUCHDB_URI=https://obsidian.jiun.dev  # 기본값
COUCHDB_USER=admin               # 기본값
COUCHDB_DB=obsidian              # 기본값
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
