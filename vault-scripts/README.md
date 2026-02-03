# Obsidian Vault Scripts

Obsidian vault 관리 자동화 스크립트입니다.

## 설치

Python 3.10+ 필요

```bash
# 의존성 설치
pip3 install --user xxhash

# 실행 권한 부여
chmod +x vault-sync.py vault-pull.py vault-cleanup.py vault-watch.sh vault-service.sh
```

---

## 스크립트 목록

| 스크립트 | 용도 |
|---------|------|
| `vault-sync.py` | JSONL → Markdown 변환, INDEX 생성 |
| `vault-pull.py` | CouchDB에서 문서 빠르게 가져오기 (LiveSync 대체) |
| `vault-cleanup.py` | 잘못된 폴더 구조 정리 |
| `vault-watch.sh` | fswatch 기반 파일 변경 감지 |
| `vault-service.sh` | launchd 서비스 관리 |
| `livesync_compat.py` | LiveSync 호환 청킹/해시 라이브러리 |
| `fix-chunks.py` | 잘못된 chunk ID 수정 (xxhash64 재생성) |

## 동기화 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                      CouchDB Server                         │
│                  (obsidian.jiun.dev)                        │
└─────────────────────────────────────────────────────────────┘
           ▲                              │
           │ push                         │ pull
           │ (LiveSync)                   │ (vault-pull.py)
           │                              ▼
┌──────────────────────┐      ┌──────────────────────┐
│   Obsidian GUI App   │◄────►│   Local Vault Files  │
│   (LiveSync Plugin)  │      │  ~/s-lastorder/      │
└──────────────────────┘      └──────────────────────┘
                                        ▲
                                        │
                              ┌─────────┴─────────┐
                              │   vault-sync.py   │
                              │  (JSONL → MD)     │
                              └───────────────────┘
```

**참고:**
- Push: Obsidian LiveSync 플러그인이 담당
- Pull: `vault-pull.py`로 빠르게 가져오기 (LiveSync보다 빠름)

---

## 1. vault-pull.py (빠른 Pull)

CouchDB에서 문서를 직접 가져옵니다. Obsidian LiveSync 플러그인보다 빠릅니다.

### 사용법

```bash
cd ~/s-lastorder/scripts

# 전체 pull
python3 vault-pull.py

# 미리보기 (변경 없음)
python3 vault-pull.py --dry-run

# 특정 경로만 pull
python3 vault-pull.py --path workspace/ssudam

# 변경된 파일만 pull (mtime 기준)
python3 vault-pull.py --changed-only

# 상세 출력
python3 vault-pull.py -v

# Orphan 파일 정리 (CouchDB에 없는 로컬 파일 삭제)
python3 vault-pull.py --delete-orphans

# Orphan 파일 미리보기
python3 vault-pull.py --delete-orphans --dry-run
```

### 옵션

| 옵션 | 설명 |
|------|------|
| `--dry-run` | 미리보기 (변경 없음) |
| `--path <prefix>` | 특정 경로만 필터링 |
| `--changed-only` | 변경된 파일만 (mtime 비교) |
| `--delete-orphans` | CouchDB에 없는 로컬 파일 삭제 |
| `-v, --verbose` | 상세 출력 |

### 특징

- **병렬 처리**: 최대 10개 동시 청크 요청
- **LiveSync 호환**: xxhash64 + Rabin-Karp 알고리즘 사용
- **mtime 보존**: 원격 문서의 수정 시간 유지
- **Orphan 정리**: 삭제 동기화 지원 (로컬에만 있는 stale 파일 제거)

---

## 2. vault-sync.py

Claude 세션을 Markdown으로 변환하고 INDEX를 생성합니다.

### 전체 동기화 (권장)

```bash
cd ~/s-lastorder/scripts

# 미리보기
python3 vault-sync.py --dry-run

# 실행 (sync → cleanup → tags → index)
python3 vault-sync.py
```

### 개별 명령

```bash
# 세션 동기화 (Claude JSONL → Markdown)
python3 vault-sync.py sync

# 세션 정리 (Warmup, 빈 파일 삭제, YAML 수정)
python3 vault-sync.py cleanup

# 태그 자동 추가 (context 문서)
python3 vault-sync.py tags

# INDEX.md 생성
python3 vault-sync.py index
```

### 옵션

| 옵션 | 설명 |
|------|------|
| `--dry-run` | 미리보기 (변경 없음) |
| `--force` | 기존 파일 덮어쓰기 |
| `--verbose`, `-v` | 상세 출력 |
| `--project <name>` | 특정 프로젝트만 |
| `--machine <name>` | 특정 머신만 (sync 명령) |

### 예시

```bash
# 특정 프로젝트만 동기화
python3 vault-sync.py sync --project ssudam

# 강제 덮어쓰기로 전체 재동기화
python3 vault-sync.py sync --force

# cleanup 미리보기
python3 vault-sync.py cleanup --dry-run

# 상세 출력으로 태그 추가
python3 vault-sync.py tags --verbose
```

---

## 3. vault-cleanup.py

잘못된 폴더 구조를 정리합니다.

### 규칙

- `workspace/ext-{name}/` → `workspace-ext/{name}/` 로 이동
- `workspace/{project}-{subdir}/` → `workspace/{project}/` 로 병합
- 잘못된 폴더명 (-, 경로 아티팩트 등) 삭제

### 사용법

```bash
# 미리보기 (필수!)
python3 vault-cleanup.py --dry-run

# 실행
python3 vault-cleanup.py
```

### 정리 대상

| 타입 | 예시 |
|------|------|
| MERGE | `ssudam-server/` → `ssudam/` |
| MERGE | `ext-clawdbot/` → `workspace-ext/clawdbot/` |
| DELETE | `workspace/-ssh/`, `workspace/workspace/` |
| MOVE | `이름 없는 보드.md` → `_misc/` |

---

## 4. livesync_compat.py (라이브러리)

Obsidian LiveSync와 동일한 청킹/해시 알고리즘을 구현합니다.

### 알고리즘

| 항목 | 알고리즘 | 설명 |
|------|----------|------|
| Hash | xxhash64 | `h:{content}-{length}` → base36 |
| Chunking | Rabin-Karp | PRIME=31, window=48 |

### 사용 예시

```python
from livesync_compat import process_document, generate_chunk_id_xxhash64

# 문서 처리
chunk_ids, chunks = process_document(content)

# 단일 청크 ID 생성
chunk_id = generate_chunk_id_xxhash64(chunk_content)
# 예: h:2kji6hwqpy7in
```

### 검증 완료

실제 CouchDB의 LiveSync 청크와 100% 일치 확인됨:
- `h:2kji6hwqpy7in` ✓
- `h:gdxmfx1izrn9` ✓
- `h:34rk352y0gfh5` ✓

---

## 5. vault-watch.sh (실시간 동기화)

fswatch를 사용한 트리거 기반 동기화 (CPU 0% - 변경 있을 때만 동작)

### 수동 실행

```bash
# 포그라운드에서 실행
./vault-watch.sh

# 백그라운드에서 실행
./vault-watch.sh &
```

### 요구사항

```bash
brew install fswatch
```

---

## 6. vault-service.sh (서비스 관리)

launchd 서비스로 백그라운드 동기화 설정

### 사용법

```bash
# 서비스 설치
./vault-service.sh install

# 서비스 제거
./vault-service.sh uninstall

# 상태 확인
./vault-service.sh status

# 로그 보기
./vault-service.sh logs
```

### 로그 위치

```
/tmp/vault-push.log
/tmp/vault-pull.log
```

---

## 동기화 경로 매핑

| 로컬 경로 | Vault 경로 |
|----------|-----------|
| `~/workspace/{project}/` | `workspace/{project}/` |
| `~/workspace-vibe/{service}/` | `workspace-vibe/{service}/` |
| `~/workspace-ext/{project}/` | `workspace-ext/{project}/` |

---

## 지원 머신

| 이름 | 타입 | 설명 |
|------|------|------|
| `local` | 로컬 | 현재 머신 |
| `jiun-mbp` | SSH | jiun-mbp 호스트 |
| `june-mbp` | SSH | june-mbp 호스트 |

새 머신 추가: `vault-sync.py`의 `MACHINES` 딕셔너리 수정

---

## 파일 구조

```
scripts/
├── README.md             # 이 파일
├── vault-sync.py         # 통합 동기화 스크립트
├── vault-pull.py         # CouchDB pull 스크립트
├── vault-cleanup.py      # 폴더 구조 정리
├── vault-watch.sh        # fswatch 트리거 동기화
├── vault-service.sh      # launchd 서비스 관리
├── livesync_compat.py    # LiveSync 호환 라이브러리
├── fix-chunks.py         # chunk ID 수정 스크립트
├── launchd/
│   ├── com.jiun.vault-push.plist
│   └── com.jiun.vault-pull.plist
└── .gitignore
```

---

## 7. fix-chunks.py (chunk ID 수정)

잘못된 hash 알고리즘으로 생성된 chunk ID를 xxhash64로 재생성합니다.

### 사용법

```bash
# 문제 문서 목록 생성 (별도 스크립트 필요)
# /tmp/problematic_docs.json 파일 필요

# 미리보기
python3 fix-chunks.py --dry-run

# 실행
python3 fix-chunks.py

# 처음 N개만 처리
python3 fix-chunks.py --limit 100
```

### 배경

LiveSync는 xxhash64 알고리즘으로 chunk ID를 생성합니다. 다른 알고리즘으로 생성된 chunk는 "waiting fetched chunks" 오류를 발생시킵니다. 이 스크립트는 문제 문서를 삭제하고 올바른 xxhash64 chunk ID로 재업로드합니다.

---

## CouchDB 설정

스크립트 내 하드코딩 (보안 주의):

```python
COUCHDB_URI = "https://obsidian.jiun.dev"
COUCHDB_USER = "admin"
COUCHDB_PASSWORD = "****"
COUCHDB_DB = "obsidian"
```

Obsidian LiveSync 플러그인과 동일한 CouchDB를 사용합니다.
