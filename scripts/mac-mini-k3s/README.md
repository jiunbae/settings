# Mac Mini M4 K3s Worker Node Setup

Mac Mini M4를 K3s 클러스터의 worker node로 설정하는 자동화 스크립트입니다.

## 아키텍처

```
┌──────────────────────────────────────────────────────────────────┐
│                        K3s Cluster                               │
├──────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │ Proxmox VM      │  │ Mac Mini #1     │  │ Mac Mini #2     │  │
│  │ (x86_64)        │  │ (arm64)         │  │ (arm64)         │  │
│  ├─────────────────┤  ├─────────────────┤  ├─────────────────┤  │
│  │ K3s Server      │  │ macOS           │  │ macOS           │  │
│  │                 │  │   └─ OrbStack   │  │   └─ OrbStack   │  │
│  │                 │  │       └─ VM     │  │       └─ VM     │  │
│  │                 │  │         └─k3s   │  │         └─k3s   │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

## 요구사항

- macOS (Apple Silicon M4 권장)
- Homebrew 설치됨
- 기존 K3s 클러스터 (server)
- K3s 클러스터와 네트워크 연결 가능

## 빠른 시작

### 1. 설정 파일 생성

```bash
cp config.env.example config.env
```

### 2. 설정 파일 편집

```bash
vim config.env
```

필수 설정:
- `K3S_URL`: K3s 서버 URL (예: `https://<YOUR_K3S_SERVER_IP>:6443`)
- `K3S_TOKEN`: K3s 노드 토큰

토큰 얻는 방법 (K3s 서버에서):
```bash
sudo cat /var/lib/rancher/k3s/server/node-token
```

### 3. 스크립트 실행

```bash
# 개발용 노드로 설정
./setup-mac-mini.sh --env dev

# 프로덕션 노드로 설정
./setup-mac-mini.sh --env prod
```

## 상세 사용법

### 명령줄 옵션

```bash
./setup-mac-mini.sh [options]

Options:
  --env ENV        환경 설정 (dev/prod), config.env 값 덮어씀
  --config FILE    커스텀 설정 파일 사용 (기본: config.env)
  --skip-orbstack  OrbStack 설치 건너뛰기
  --skip-vm        VM 생성 건너뛰기
  --skip-network   네트워크 설정 건너뛰기
  --skip-k3s       K3s 설치 건너뛰기
  --tailscale      Tailscale 설치 (오버레이 네트워킹)
  --dry-run        실제 실행 없이 계획만 출력
  -h, --help       도움말 표시
```

### 예시

```bash
# 기본 설치
./setup-mac-mini.sh

# 프로덕션 환경으로 설정
./setup-mac-mini.sh --env prod

# Tailscale로 네트워크 구성
./setup-mac-mini.sh --tailscale

# 다른 설정 파일 사용
./setup-mac-mini.sh --config /path/to/my-config.env

# 테스트 실행 (실제 변경 없음)
./setup-mac-mini.sh --dry-run
```

## 설정 옵션

### config.env 설정 항목

| 항목 | 설명 | 기본값 |
|------|------|--------|
| `K3S_URL` | K3s 서버 URL | (필수) |
| `K3S_TOKEN` | K3s 노드 토큰 | (필수) |
| `NODE_NAME` | 노드 이름 | `mac-mini-worker` |
| `NODE_ENV` | 환경 (dev/prod) | `dev` |
| `NODE_PURPOSE` | 용도 라벨 | `general` |
| `VM_NAME` | OrbStack VM 이름 | `k3s-worker` |
| `UBUNTU_VERSION` | Ubuntu 버전 | `22.04` |
| `NETWORK_MODE` | 네트워크 모드 (nat/bridge) | `nat` |

## 네트워크 설정

### NAT 모드 (기본)

OrbStack의 NAT 네트워크를 사용합니다. 대부분의 경우 이 모드로 충분합니다.

```env
NETWORK_MODE="nat"
```

**주의**: NAT 모드에서는 K3s 서버가 Mac Mini의 VM에 직접 접근할 수 없습니다.
NodePort 서비스 등에 제한이 있을 수 있습니다.

### Tailscale 오버레이 네트워킹 (권장)

네트워크 제한을 우회하려면 Tailscale을 사용하세요:

```bash
./setup-mac-mini.sh --tailscale
```

설치 후 VM에서:
```bash
orb shell k3s-worker
sudo tailscale up
```

## 문제 해결

### OrbStack이 시작되지 않음

```bash
# OrbStack 수동 시작
open -a OrbStack

# 상태 확인
orb status
```

### K3s 연결 실패

```bash
# VM에서 K3s 서버 연결 테스트
orb -m k3s-worker curl -sk https://<YOUR_K3S_SERVER_IP>:6443/healthz

# K3s 에이전트 로그 확인
orb -m k3s-worker sudo journalctl -u k3s-agent -f
```

### 노드가 클러스터에 표시되지 않음

```bash
# K3s 서버에서 노드 확인
kubectl get nodes -o wide

# 노드 상태 확인
kubectl describe node <node-name>
```

### VM 재시작

```bash
# VM 중지
orb stop k3s-worker

# VM 시작
orb start k3s-worker

# K3s 에이전트는 자동으로 시작됨
```

## 노드 라벨

설치 후 노드에는 다음 라벨이 적용됩니다:

- `env=dev` 또는 `env=prod`
- `purpose=general` (또는 설정값)
- `kubernetes.io/arch=arm64`

### 라벨로 워크로드 스케줄링

```yaml
# ARM64 노드에만 배포
spec:
  nodeSelector:
    kubernetes.io/arch: arm64

# 개발 환경에만 배포
spec:
  nodeSelector:
    env: dev
```

## 참고 자료

- [K3s Documentation](https://docs.k3s.io/)
- [OrbStack Documentation](https://docs.orbstack.dev/)
- [Multi-arch Kubernetes Clusters](https://cablespaghetti.dev/2021/02/20/managing-multi-arch-kubernetes-clusters/)
