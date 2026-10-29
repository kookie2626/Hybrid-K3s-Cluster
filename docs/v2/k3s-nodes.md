# N100 control plane / N5095 application worker

기존 OS 설치 기록: [N100](../01-n100-서버-셋업.md), [N5095](../08-n5095-워커-노드-추가.md). 기존 클러스터가 있다면 재설치하지 않고 노드 상태부터 확인합니다. 아래 설치는 신규 노드용이며 OS·K3s 버전을 운영 기록에 남깁니다.

1. 서로 다른 hostname, 고정 IP, 시간 동기화, SSH 키를 준비합니다.
2. [네트워크 계약](architecture.md)에 맞게 방화벽을 구성합니다. 기존 문서의 UFW SSH-only 설정만으로 K3s가 동작한다고 가정하지 않습니다.
3. 신규 N100에서 공식 설치 스크립트를 내려받아 검토하고, 선택한 버전을 고정해 server를 설치합니다.

```bash
curl -sfL https://get.k3s.io -o /tmp/install-k3s.sh
# 검토 후 검증한 실제 릴리스 태그 지정
export INSTALL_K3S_VERSION='<검증한-K3s-릴리스-태그>'
sudo env INSTALL_K3S_VERSION="$INSTALL_K3S_VERSION" sh /tmp/install-k3s.sh server --node-name n100
```

N100의 /var/lib/rancher/k3s/server/node-token을 안전한 경로로 전달합니다. N5095의 root 전용 /etc/rancher/k3s/agent-token 파일에 저장하고 권한을 600으로 설정합니다. 토큰·kubeconfig는 커밋하지 않습니다.

```bash
# N5095: 위와 같이 설치 스크립트 검토, server와 같은 버전 사용
export INSTALL_K3S_VERSION='<N100과-동일한-릴리스-태그>'
export N100_IP='<N100-LAN-IP>'
sudo env INSTALL_K3S_VERSION="$INSTALL_K3S_VERSION" \
  K3S_URL="https://$N100_IP:6443" \
  K3S_TOKEN_FILE=/etc/rancher/k3s/agent-token \
  sh /tmp/install-k3s.sh agent --node-name n5095-worker
```

관리 kubeconfig를 안전하게 설정한 후 실제 노드 이름을 확인합니다. 기존 노드 이름이 다르면 아래 명령을 맞춥니다.

```bash
kubectl get nodes -o wide
kubectl label node n100 workload=infra --overwrite
kubectl label node n5095-worker workload=apps --overwrite
kubectl get nodes -L workload
```

앱 Deployment의 spec.template.spec.nodeSelector에 workload: apps를 지정하고 requests/limits, readiness/liveness probe를 추가합니다. inference 장애가 앱 프로세스 liveness 실패를 유발해 재시작 루프가 되지 않게 합니다. N100 인프라 selector는 workload: infra입니다.

완료 기준: 두 Linux 노드 Ready, Pod DNS 및 노드 간 통신 성공, N5095에 앱 배치 확인. Mac mini는 kubectl get nodes 목록에 나타나지 않습니다. 출력 예시를 실제 검증 증거로 사용하지 않습니다.
