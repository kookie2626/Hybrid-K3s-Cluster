# v2 설계 결정

## 역할과 대안

Mac mini M4 Pro는 macOS 네이티브 AI 서버로 두고 Apple GPU를 활용하는 Ollama를 우선 검증합니다. Linux VM worker로 넣으면 클러스터 운영과 모델 서빙의 장애·업데이트 경계가 얽히므로 v2에서는 제외합니다. MLX 기반 서빙은 API 호환성·운영 복잡도·성능을 측정한 뒤 별도 결정합니다. vLLM을 macOS 기본 경로로 가정하지 않습니다.

N100은 control plane 및 작은 인프라 워크로드, N5095는 앱을 담당합니다. label만으로 자동 격리되지는 않습니다. 앱에는 nodeSelector를, 향후 ingress/Prometheus/Grafana 배포에는 infra selector를 명시합니다. 시스템 DaemonSet은 양쪽 노드에 실행될 수 있습니다. N100에 blanket taint를 추가하기 전 CoreDNS/ingress 등의 스케줄링을 검토합니다.

## 네트워크 계약

모든 주소는 DHCP reservation 또는 고정 IP로 관리합니다. 실제 주소를 저장소에 넣을 필요는 없습니다.

| 흐름 | 포트 | 허용 범위 |
|---|---|---|
| 관리 → Linux/macOS | TCP 22 | 관리 LAN/VPN |
| agent/관리 → N100 | TCP 6443 | 노드/관리 LAN/VPN |
| Linux 노드 간 Flannel VXLAN | UDP 8472 | Linux 노드 IP 사이 |
| Linux 노드 간 kubelet | TCP 10250 | 필요한 클러스터 트래픽 |
| K3s → Mac mini Ollama | TCP 11434 | 실제 egress 원본만 |
| 모니터링 → node-exporter | TCP 9100 | 수집기만 |

Pod에서 LAN으로 나갈 때 원본이 노드 IP로 SNAT되는지 패킷/접속 로그로 확인합니다. custom CNI/라우팅을 쓰면 원본이 Pod CIDR일 수 있습니다. macOS 방화벽/네트워크 ACL은 실제 원본 기준으로 제한합니다. 11434와 6443을 공유기에서 공인망으로 포워딩하지 않습니다. 원격 관리는 VPN을 사용합니다.

## 자원과 가용성

N100의 control plane 자원을 우선 확보하고 관측 스택의 보존 기간·디스크 사용을 제한합니다. N5095의 기존 8GB 메모리 기록을 기준으로 작은 API부터 시작하며 vector DB와 대형 ingestion을 동시에 올리지 않습니다. PVC는 노드 로컬 스토리지일 수 있으므로 다른 노드로 자동 복구된다고 가정하지 않습니다. N100 datastore와 앱 데이터를 별도 백업하고 실제 복원 시험을 남깁니다.

[공식 K3s 네트워크 요구사항](https://docs.k3s.io/installation/requirements)을 사용 중인 버전과 대조합니다.
