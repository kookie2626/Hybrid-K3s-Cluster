# 아이맥(iMac M1)에 Lima로 K3s 워커 노드 구성하기

## 배경

아이맥 M1은 집에서 주로 사용하는 기기이기 때문에, 항상 켜 둔 채 고사양 작업을 처리하는 역할에 적합합니다.
그러나 macOS를 완전히 삭제하고 Ubuntu를 설치하기 어려운 환경(Apple Silicon)이므로,
**Lima(Linux on Mac)** 를 사용해 macOS 위에서 경량 Ubuntu VM을 실행하고, 그 안에 K3s 에이전트를 설치했습니다.

> 💡 Lima는 macOS에서 공식 지원하는 QEMU 기반 Linux VM 관리 도구로,  
> Docker Desktop 없이도 Apple Silicon에서 ARM64 Ubuntu를 바로 실행할 수 있습니다.

---

## 하드웨어 사양

| 항목 | 사양 |
|------|------|
| 모델 | iMac (2021, Apple M1) |
| CPU | Apple M1 (8코어: 4성능 + 4효율) |
| RAM | 16GB Unified Memory |
| Storage | 512GB SSD |
| 아키텍처 | ARM64 (Apple Silicon) → Lima VM으로 Ubuntu 실행 |

---

## Lima 설치

### 1. Homebrew로 Lima 설치

```bash
# Homebrew가 없는 경우 먼저 설치
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Lima 설치
brew install lima

# 설치 확인
limactl --version
```

---

## Lima VM 생성 및 설정

### 2. VM 템플릿 사용

저장소에 준비된 Lima 설정 파일을 사용합니다:

```bash
# 저장소 루트에서 실행
limactl start --name=k3s-worker scripts/setup/lima-ubuntu-k3s.yaml
```

이 설정 파일의 주요 내용:

| 항목 | 값 |
|------|-----|
| OS | Ubuntu 22.04 LTS |
| 아키텍처 | aarch64 (Apple Silicon 기본) |
| vCPU | 4코어 |
| vRAM | 8GiB |
| Disk | 40GiB |
| 네트워크 | shared (Lima의 공유 네트워크, LAN 접근 가능) |
| 포트 포워딩 | 6443 (K3s API) — 게스트 → 호스트 |

### 3. VM 상태 확인

```bash
# 실행 중인 VM 목록 확인
limactl list

# VM 접속
limactl shell k3s-worker
```

---

## K3s 에이전트 설치 (VM 내부)

### 4. VM 내에서 K3s 에이전트 등록

마스터 노드(N100)의 IP와 토큰을 확인한 후 VM 내부에서 실행합니다:

```bash
# 마스터 노드에서 토큰 확인 (N100 서버에서)
sudo cat /var/lib/rancher/k3s/server/node-token

# Lima VM 내부에서 K3s 에이전트 설치
limactl shell k3s-worker -- sudo bash -c "
  curl -sfL https://get.k3s.io | \
    K3S_URL='https://<MASTER_IP>:6443' \
    K3S_TOKEN='<NODE_TOKEN>' \
    sh -
"
```

또는 자동화 스크립트를 사용합니다:

```bash
# 스크립트 실행 (저장소 루트에서)
chmod +x scripts/setup/lima-k3s-setup.sh
./scripts/setup/lima-k3s-setup.sh
```

스크립트가 자동으로 아래 작업을 수행합니다:
- Homebrew / Lima 설치 여부 확인 및 설치
- VM 생성 (없는 경우) 또는 기동
- VM 내부에서 K3s 에이전트 설치 및 마스터 연결

---

## 네트워크 트러블슈팅

Lima의 기본 네트워크 모드는 **NAT**입니다. 이 경우 VM에서 외부(LAN)로 나가는 아웃바운드는 가능하지만,
VM의 주소가 직접 LAN에 노출되지 않아 K3s 마스터가 에이전트를 역방향으로 연결할 때 문제가 생길 수 있습니다.

### 문제 증상

```
FATA[0000] starting kubernetes: connecting to server:
  dial tcp 192.168.1.10:6443: connect: connection refused
```

### 해결 방법: 포트 포워딩 설정

`lima-ubuntu-k3s.yaml`에 포함된 `portForwards` 블록이 이 문제를 해결합니다:

```yaml
portForwards:
  - guestPort: 6443
    hostPort: 6443
    hostIP: "0.0.0.0"
```

설정 변경 후 VM을 재시작합니다:

```bash
limactl stop k3s-worker
limactl start k3s-worker
```

마스터 노드에서 포트가 열려 있는지 확인합니다:

```bash
# N100 마스터에서 실행
sudo netstat -tlnp | grep 6443
# tcp6  0  0 :::6443  :::*  LISTEN  ... k3s
```

---

## VM 일상 관리

```bash
# VM 시작 (iMac 재부팅 후)
limactl start k3s-worker

# VM 중지
limactl stop k3s-worker

# VM 내부 shell 접속
limactl shell k3s-worker

# K3s 에이전트 상태 확인 (VM 내부)
limactl shell k3s-worker -- sudo systemctl status k3s-agent
```

---

## 결과

Lima VM 내부에 K3s 에이전트가 정상적으로 설치되어 N100 마스터 노드에 워커로 합류했습니다.

```bash
# N100 마스터 노드에서 확인
kubectl get nodes
# NAME            STATUS   ROLES                  AGE
# n100            Ready    control-plane,master   7d
# mbp-2014        Ready    <none>                 5d
# lima-k3s-worker Ready    <none>                 1d
```

아이맥 M1의 높은 연산 성능(Apple M1 8코어)을 K3s 클러스터의 고사양 워크로드 처리에 활용할 수 있게 되었습니다.
