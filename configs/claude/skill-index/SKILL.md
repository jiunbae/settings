---
name: skill-index
description: >-
  Catalog of the nested skills under ~/.claude/skills that Claude Code does not
  auto-discover (they live one directory deeper than the harness scans). Load this
  whenever a task touches Callabo (auth, mongodb, notion, slack, records, insights,
  labels, amplitude, metabase, blog, image, voiceprint, speaker, transcription,
  member matching, poc analytics, competitor analysis, crm, product info, workspace
  health/audit, resolve, callabo-set), an integration (kibana/로그, linear/이슈,
  notion/노션, sentry/에러), Pronaia ML work (audio, triton, model sync, benchmark),
  or managing services and Obsidian notes — or whenever the user asks what skills
  exist. It maps each skill to its SKILL.md path so the right one can be read on
  demand instead of loading all of them every session. Skills that already load at
  depth 1 (korean-editor, rpf, grill-me, static-index, context-manager,
  git-commit-pr, security-auditor, background-*) are NOT listed here — the harness
  already surfaces them, so do not read this index looking for those.
---

# Skill Index

`~/.claude/skills` 아래 **39개** 스킬이 카테고리 디렉토리 안에 있습니다.
Claude Code는 `~/.claude/skills/<이름>/SKILL.md` **한 depth만** 스캔하므로 이 스킬들은
자동 로딩되지 않습니다. 대신 이 인덱스를 통해 필요할 때만 꺼내 씁니다.

## 사용법

1. 아래 표에서 작업에 맞는 스킬을 찾는다.
2. 해당 `SKILL.md`를 **Read** 한다.
3. 그 내용을 정식으로 호출된 스킬처럼 그대로 따른다 (스크립트 경로·환경변수 포함).

디렉토리명 == frontmatter `name` 이 항상 성립하므로, 경로는
`~/.claude/skills/<카테고리>/<이름>/SKILL.md` 로 바로 조립할 수 있습니다.

> `~/.agents/*.md` 는 별개입니다 — SessionStart 훅이 실제로 존재하는 파일만 골라
> 트리거와 함께 요약해 주입하므로, 파일명을 여기서 추측하지 말고 그 요약을 보세요.
> 스크립트 래퍼와 상세 절차가 필요할 때 아래 `integration-*` 스킬을 읽으세요.

## callabo — Callabo 서비스

| 스킬 | 트리거 | 설명 |
|---|---|---|
| `callabo-ai-copilot` ↗ | - ai copilot - AI 코파일럿 - 회의 질문 - meeting Q&A - ask meeting - 회의 분석 - 대화형 분석 - chat with meetings - 미팅 챗 | AI 코파일럿 - 회의 내용에 자연어로 질문하는 대화형 분석. Natural language Q&A across meeting records with conversational AI. |
| `callabo-amplitude` ↗ | amplitude, analytics, event, 분석, 이벤트, funnel, 퍼널, tracking, user behavior, 사용자 행동 | Amplitude analytics integration for user behavior analysis, event tracking, funnel analysis, and automated reports. Activated when users mention "Amplitude", "analytics", "event tracking"… |
| `callabo-auth` ↗ | auth, login, authenticate, token, 인증, 로그인, 토큰, OAuth, credentials, 자격증명, refresh token | Authentication skill for Callabo API - handles login, OAuth (Google/Apple/Microsoft), 2FA, token management, and session handling. 인증, 로그인, 토큰 관리 기능을 제공합니다. |
| `callabo-auto-label` ↗ | auto label, automatic, 자동 라벨, 자동 분류, AI labeling, categorize, content analysis, 콘텐츠 분석 | Auto-labeling skill for Callabo records - analyzes content and automatically suggests/applies appropriate labels with AI-powered recommendations. 자동 라벨링, AI 분류, 콘텐츠 분석 기능을 제공합니다. |
| `callabo-blog-generator` ↗ | - 블로그 생성 - blog generator - SEO 최적화 - 제품 소개 글 - feature article - callabo blog | AI-powered blog content generator for Callabo product/feature articles with SEO optimization for callabo.ai/blog (inblog.dev platform). Callabo 제품/기능 소개 블로그 콘텐츠 생성, SEO 최적화, 다중 포맷 출력(Mark… |
| `callabo-blog-writer` ↗ | - 블로그 작성 - 블로그 써줘 - 블로그 글 작성 - blog write - 콘텐츠 작성 - 포스트 생성 - 글 써줘 - 아티클 작성 | 콜라보 블로그 작성 에이전트. callabo.ai/blog 스타일에 맞춘 7가지 글 유형 (제품가이드, 제품비교, 경험공유, 업데이트노트, 체크리스트, 전문가이드, 인사이트)의 SEO 최적화 콘텐츠를 생성합니다. 주제 분석부터 Notion 발행까지 자동화된 워크플로우를 제공합니다. [경계] 7유형 작성→Notion 발행 오케스트레이션… |
| `callabo-competitor-analysis` ↗ | - 경쟁사 분석 - competitor analysis - 시장 조사 - 가격 비교 - Otter.ai - 클로바노트 - Fireflies - 경쟁사 동향 - 티로 - tl;dv - Gong - Fathom | AI 웹 검색 기반 경쟁사 분석 및 비교 리포트 생성. 가격/기능/시장 데이터를 수집하여 비교표, Slack 알림, Metabase 대시보드로 출력합니다. |
| `callabo-crm-sync` ↗ | - crm sync - CRM 동기화 - salesforce - 세일즈포스 - pipedrive - 파이프드라이브 - crm export - CRM 내보내기 - 고객 연동 | CRM 동기화 - Salesforce/Pipedrive와 회의 기록 연동. Sync meeting records with CRM systems for sales automation. |
| `callabo-image-generator` ↗ |  | Z-Image API를 사용한 AI 이미지 생성/편집/분석. 블로그 썸네일, 마케팅 이미지, UI 스크린샷 분석 지원. "이미지 생성", "썸네일", "image", "txt2img", "img2img", "이미지 분석", "VLM" 키워드로 활성화. (project) |
| `callabo-insights` ↗ | insight, summary, 인사이트, 요약, meeting notes, 회의록, action items, 액션 아이템, keywords, 키워드 | Retrieve, analyze, compare, and aggregate AI-generated insights from meeting records with advanced filtering and reporting. Activated when users ask about summaries, action items, meeting… |
| `callabo-labels` ↗ | label, tag, 라벨, 태그, categorize, 분류, assign label, 라벨 할당 | Label management skill for Callabo API - create, read, update, delete labels and manage label assignments to records. 라벨 관리, 태그 생성, 레코드 분류 기능을 제공합니다. |
| `callabo-media-download` ↗ | media, download, audio, video, 다운로드, 미디어, extract audio, 오디오 추출, wav, mp4 | Download original media files from Callabo records with automatic format conversion and retry logic for voiceprint analysis. Activated when users need audio extraction, media download, or… |
| `callabo-member-matching` ↗ | member matching, speaker, 화자, 성문, voiceprint, 매칭, speaker identification, 화자 식별, match speaker | Match record speakers to workspace members using voiceprint analysis, email matching, and cross-record learning with automatic speaker_info updates. Activated when users mention "speaker… |
| `callabo-metabase` ↗ | metabase, dashboard, BI, 대시보드, analytics, 분석, MRR, ARR, revenue, question, SQL | Metabase BI platform integration for dashboards, questions, data analytics, and revenue metrics. Activated when users mention "Metabase", "dashboard", "MRR", "analytics", or need BI repor… |
| `callabo-mongodb` ↗ | - mongodb - 몽고 - 데이터베이스 - DB - 데이터 저장 - 데이터 조회 - voiceprint DB - 스킬 데이터 | Callabo 스킬 데이터를 MongoDB로 관리합니다. Docker 컨테이너 자동 관리, 데이터 영속성, 스킬 간 데이터 공유를 지원합니다. |
| `callabo-notion` ↗ | notion, 노션, sync, 동기화, meeting notes, 회의록, export, 내보내기, wiki, 문서화, page, database | Notion integration for Callabo - sync meeting notes, action items, and summaries to Notion pages and databases. Full CRUD for pages, databases, and blocks. 노션 연동, 회의록 동기화, 액션 아이템 내보내기, 데이… |
| `callabo-poc-analytics` ↗ | - POC 분석 - POC 리포트 - 사용 지표 - 계약 협상 - 고객 분석 - Remember - 리멤버 - poc metrics - usage analytics | POC 고객의 사용 지표를 분석하고 계약 협상용 대시보드/리포트를 생성합니다. Activated when users need POC metrics, usage analysis, or contract negotiation reports. |
| `callabo-product-info` ↗ | - 콜라보 기능 - callabo 가격 - 요금제 - 콜라보 뭐야 - 콜라보 소개 - 제품 정보 - 어떤 서비스 - 콜라보 연동 - 콜라보 보안 - 콜라보 언어 - 콜라보 지원 언어 - 화상회의 지원 - 앱 다운로드 | 콜라보(Callabo) 제품의 공개 정보를 기반으로 기능, 요금제, 연동, 보안 등 제품 정보를 정확하게 제공합니다. 내부 API/데이터는 사용하지 않습니다. |
| `callabo-records` ↗ | record, 레코드, 녹음, meeting, 미팅, recording, transcription, dialog, 대화, list records | Records management for Callabo API - list, search, filter, and retrieve record details with transcription and insights. Activated when users need to find meetings, view transcriptions, or… |
| `callabo-resolve` ↗ |  | Resolve a Callabo Linear issue end-to-end when the user gives a CAL-XXXX identifier and asks to resolve, start, or implement it. Reuses or creates exactly one callabo-set workspace per is… |
| `callabo-set` ↗ |  | Local Callabo dev environment skill — create exactly one registry-driven workspace per work item, add or run selected service repositories, sync dev DB, manage shared MySQL/Redis/Elastics… |
| `callabo-skill-generator` ↗ | skill, generate, create skill, 스킬 생성, template, 템플릿, new skill, skill development | Generate well-structured Claude Code skills following best practices and guidelines for skill development. 스킬 생성, 템플릿 제공, 베스트 프랙티스 가이드 기능을 제공합니다. |
| `callabo-slack` ↗ | slack, notification, 알림, message, 메시지, report, 리포트, webhook, channel | Slack webhook integration skill for Callabo - send notifications, alerts, and messages to Slack channels with rich formatting. Slack 알림, 메시지 전송, 리포트 공유 기능을 제공합니다. |
| `callabo-speaker-update` ↗ | speaker, 화자, 스피커, speaker-info, rename speaker, update speaker, 화자 이름, 스피커 업데이트, speaker name | Update speaker names in Callabo records via speaker-info API. Map speaker IDs to actual names for better transcription readability. Activated when users want to rename speakers, update sp… |
| `callabo-transcription-check` ↗ | transcription, 전사, quality, 품질, check, 검사, validation, 검증, STT, speech to text, error detection | Analyzes Record dialogues for transcription errors with AI-powered word-level detection, speaker-aware analysis, and workspace keyword filtering. 전사 품질 검증, 오류 탐지, 리포트 생성 기능을 제공합니다. |
| `callabo-voiceprint` ↗ | voiceprint, voice, 성문, 음성 지문, speaker recognition, 화자 인식, voice embedding, biometric, ECAPA-TDNN | Extract voiceprints from audio files and match speakers across records using AI-powered voice biometric analysis. 성문 매칭, 음성 지문 분석, 화자 인식을 위한 AI 기반 음성 생체 인식 분석 도구입니다. |
| `callabo-workspace-audit` ↗ |  | 워크스페이스 폴더 전체를 점검하여 Linear 이슈 상태(Done/In Progress/Triage)와 GitHub PR 상태(Merged/Open/Closed)를 조사하고 보고합니다. 정리 가능한 폴더, 진행 중인 작업, 주의가 필요한 항목을 분류합니다. Audit all workspace folders, check Linear i… |
| `callabo-workspace-health` ↗ | - workspace health - 워크스페이스 헬스 - quota - 쿼터 - usage - 사용량 - license - 라이선스 - health check - 상태 확인 - 이탈 방지 | 워크스페이스 사용량/쿼터 모니터링 및 헬스 스코어 분석. 고객 이탈 방지를 위한 사전 알림 시스템. Workspace health monitoring, quota alerts, and churn prevention. |
| `fetch-openapi` ↗ | openapi, swagger, api docs, api spec, 스웨거, API 문서, endpoint, 엔드포인트 | Fetch the latest Callabo OpenAPI specification from dev-api.callabo.ai. Activated when users need API specs, swagger docs, endpoint references, or want to explore available APIs. OpenAPI… |

## integration — 외부 서비스 연동

| 스킬 | 트리거 | 설명 |
|---|---|---|
| `integration-kibana` ↗ | kibana, 키바나, elasticsearch, 엘라스틱서치, log, 로그, 프로덕션 로그, production log, 500 error, transaction trace, 트랜잭션 추적, aggregation, 집계 | Kibana 로그 검색/분석 스킬 - 조건(시간 범위, KQL/Lucene 쿼리, 인덱스 패턴)으로 Elasticsearch 로그를 조회하고, transaction ID 추적, 필드 집계를 수행합니다. 문제 분석용 read-only 로그 watcher. |
| `integration-linear` ↗ |  | Linear 이슈 조회/생성 스킬 - 이슈 번호(CAL-1234) 또는 키워드로 검색하고, 새 이슈를 생성합니다. 생성은 dry-run이 기본이며 --execute 플래그로 실제 생성합니다. |
| `integration-notion` ↗ | notion, 노션, 노션 검색, 노션 조회, 페이지 생성, 문서 업로드, notion search, notion create, 노션 페이지, 노션 정리 | Notion 통합 스킬 - 페이지/데이터베이스 검색, 문서 조회, 지정 위치에 문서 생성, 마크다운 업로드. Notion integration for searching pages, reading content, creating documents at specified locations, and uploading markdown fil… |
| `integration-sentry` ↗ |  | Sentry 이슈 조회 스킬 - 이슈 ID, 에러 메시지, 프로젝트별로 Sentry 이벤트를 검색하고 stack trace, tags, breadcrumbs를 가져옵니다. Sentry issue lookup for error investigation via REST API. |

## integrations — 외부 서비스 연동 (구)

| 스킬 | 트리거 | 설명 |
|---|---|---|
| `managing-services` ↗ | 서비스 등록, 서비스 목록, 포트 확인, 컨테이너 관리, docker 상태 | Centrally manages Docker containers and services. Supports service registration, listing, status updates, and port conflict detection. Use for "서비스 등록", "서비스 목록", "포트 확인", "컨테이너 관리", "doc… |
| `obsidian-writer` ↗ |  | Save project context and articles to the configured Obsidian Vault, and publish Markdown to docs.jiun.dev through the Vault sync workflow. Use for "obsidian 업로드", "옵시디언 저장", "vault 업로드",… |

## pronaia — Pronaia / ML

| 스킬 | 트리거 | 설명 |
|---|---|---|
| `benchmarking-ml-models` ↗ |  | Runs ML model benchmarks and evaluations. Measures inference speed, memory usage, and accuracy metrics. Use for "벤치마크", "모델 평가", "성능 테스트", "inference 속도" requests. |
| `deploying-triton` ↗ |  | Deploys and manages NVIDIA Triton Inference Server containers. Automates model repository setup, config generation, and health checks. Use for "triton 서버", "triton 실행", "모델 서빙", "inferenc… |
| `processing-audio` ↗ |  | Converts and processes audio files using ffmpeg. Supports format conversion, sample rate changes, mono/stereo conversion, and segment splitting. Use for "오디오 변환", "wav 변환", "샘플레이트", "ffmp… |
| `syncing-ml-models` ↗ |  | Synchronizes ML model files across servers. Supports rsync-based transfer with bandwidth control and checksum verification. Use for "모델 동기화", "모델 배포", "rsync 모델", "서버로 전송" requests. |

↗ = 소스 레포(`~/workspace/agents`, `~/personal/agent-skills`)로의 심볼릭 링크.
내용을 고치면 레포가 수정되니 커밋 여부를 확인하세요.

## 유지보수

스킬을 추가·삭제한 뒤에는 인덱스를 재생성합니다:

```bash
python3 ~/.claude/skills/skill-index/build.py
```

규칙: 새 스킬의 디렉토리명은 frontmatter `name` 과 **정확히 일치**해야 하고,
frontmatter 키는 `name`, `description`, `allowed-tools`, `license`, `metadata` 만
허용됩니다 (`trigger-keywords`, `tags`, `priority` 는 스펙 외 — 트리거는
`triggers.json` 또는 `description` 에 넣으세요).
