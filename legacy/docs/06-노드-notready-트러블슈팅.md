# 쿠버네티스 노드 NotReady 해결 가이드 (iMac Lima 워커 노드)

> Lima 가상 머신 환경에서 발생하는 네트워크 단절로 인한 `NotReady` 문제를 진단하고 복구하는 방법을 설명합니다.

---

## 1. 현상 (Issue)

**상황**: 마스터 노드(N100)에서 `kubectl get nodes` 확인 시 `lima-default` 노드가 `NotReady` 상태로 표시됩니다.

```bash
# N100 마스터 노드에서 실행
kubectl get nodes
# NAME            STATUS     ROLES                  AGE
# n100            Ready      control-plane,master   5d
# mbp-2014        Ready      <none>                 3d
# lima-default    NotReady   <none>                 2d   ← 문제
```

**Lima 내부 k3s-agent 로그 에러 메시지**:

```
failed to validate connection to cluster at https://192.168.75.40:6443: connection reset by peer
```

**특이사항**: 마스터 노드의 `6443` 포트는 열려 있고 방화벽(`ufw`) 설정도 정상이나 에이전트 통신이 거부됩니다.

---

## 2. 원인 분석 (Root Cause)

Lima VM과 macOS 호스트 사이의 **포트 포워딩 연결 고리**가 끊어지는 것이 핵심 원인입니다.

| 요인 | 상세 내용 |
|------|-----------|
| 네트워크 브릿지 단절 | iMac(M1)의 잠자기 모드 진입, Wi-Fi 재연결 등 네트워크 환경 변화 시 Lima의 포트 포워딩 터널이 끊어짐 |
| 에이전트 통신 불능 | Lima VM 내부 `k3s-agent` 프로세스는 `Running` 상태이지만, 마스터 노드와의 데이터 통로가 막혀 Heartbeat 전송 불가 |
| 결과 | 마스터 노드가 에이전트로부터 주기적인 상태 보고를 받지 못해 노드를 `NotReady`로 판단 |

```
[ iMac 호스트 ] <-- 포트 포워딩 끊어짐 --> [ Lima VM (k3s-agent) ]
       ↕                                             ↕
[ N100 마스터 ]  <-- Heartbeat 수신 불가  -->  [ k3s-agent ]
```

---

## 3. 해결 방법 (Resolution Steps)

### Step 1: Lima 가상 머신 및 포트 포워딩 초기화

호스트와 게스트 간의 네트워크 터널을 재구동합니다. **iMac 터미널에서 실행합니다.**

```bash
# iMac 터미널에서 실행 (VM 이름이 다른 경우 'default'를 해당 이름으로 교체)
limactl stop default
limactl start default
```

> 💡 `limactl list` 명령어로 VM 이름을 확인할 수 있습니다.

---

### Step 2: k3s-agent 서비스 재시작

네트워크가 복구된 후 에이전트가 마스터와 다시 핸드셰이크하도록 유도합니다. **Lima 내부에서 실행합니다.**

```bash
# 방법 A: iMac 터미널에서 Lima shell을 통해 실행
lima sudo systemctl restart k3s-agent

# 방법 B: Lima shell에 직접 접속 후 실행
limactl shell default
sudo systemctl restart k3s-agent
```

---

### Step 3: 상태 확인

에이전트 재시작 후 약 30초~1분 뒤 마스터에서 노드 상태를 확인합니다.

```bash
# N100 마스터 터미널에서 실행
kubectl get nodes
# NAME            STATUS   ROLES                  AGE
# n100            Ready    control-plane,master   5d
# mbp-2014        Ready    <none>                 3d
# lima-default    Ready    <none>                 2d   ← 복구 확인
```

여전히 `NotReady`인 경우 에이전트 로그를 직접 확인합니다:

```bash
# Lima 내부에서 실행
lima sudo journalctl -u k3s-agent -f --no-pager
```

---

## 4. 진단 체크리스트

복구 전 빠르게 원인을 파악하기 위한 확인 순서입니다.

| 순서 | 확인 항목 | 명령어 | 예상 정상 결과 |
|------|-----------|--------|----------------|
| 1 | Lima VM 실행 상태 | `limactl list` | STATUS가 `Running` |
| 2 | k3s-agent 서비스 상태 | `lima sudo systemctl status k3s-agent` | `active (running)` |
| 3 | 마스터 포트 접근 가능 여부 | `lima curl -k https://<MASTER_IP>:6443` | HTTP 응답 반환 (403 등) |
| 4 | 에이전트 로그 확인 | `lima sudo journalctl -u k3s-agent -n 50` | 최근 에러 내용 확인 |

---

## 5. 예방 조치 (Best Practices)

### 아이맥 잠자기 방지

네트워크 서비스가 유지되도록 시스템 설정을 변경합니다.

1. **시스템 설정** → **디스플레이** → 디스플레이가 꺼져도 컴퓨터가 잠들지 않도록 설정
2. 또는 **시스템 설정** → **배터리** → "네트워크 접근 시 깨우기" 활성화

### Tailscale(VPN) 활용

Wi-Fi 재연결 등 네트워크 환경 변화에 유연하게 대응하기 위해, 마스터 서버 주소로 **Tailscale IP**를 사용하는 것을 권장합니다.

```bash
# k3s-agent 설치 시 Tailscale IP를 마스터 주소로 지정
curl -sfL https://get.k3s.io | \
  K3S_URL='https://<TAILSCALE_MASTER_IP>:6443' \
  K3S_TOKEN='<NODE_TOKEN>' \
  sh -
```

### Lima VM 자동 시작 설정

iMac 재부팅 후 Lima VM이 자동으로 기동되도록 launchd를 활용합니다.

```bash
# Lima 공식 autostart 설정 (Lima 0.14+ 지원)
limactl start --name=default
# 이후 macOS 로그인 항목에 limactl을 추가하거나,
# ~/Library/LaunchAgents/ 에 plist 파일을 생성하여 자동화할 수 있습니다.
```

---

## 6. 관련 문서

- [04-아이맥-lima-설치.md](04-아이맥-lima-설치.md) — Lima 초기 설치 및 K3s 에이전트 등록 전체 가이드
- [Lima 공식 문서](https://lima-vm.io/) — Lima 네트워크 모드 및 포트 포워딩 상세 설명
