# 모니터링 및 운영 계획

기존 manifests/monitoring/node-exporter-daemonset.yaml은 Linux 노드 지표 노출 예제입니다. Prometheus/Grafana, scrape 설정, 알림과 macOS 수집기를 설치하지 않습니다. DaemonSet의 host mount/hostNetwork 권한과 이미지 버전을 검토한 뒤 적용합니다.

## 단계별 도입

1. Linux exporter를 검증하고 Prometheus 수집 대상으로 등록합니다. 기존 headless Service의 각 endpoint를 scrape하도록 구성해 두 노드가 각각 up=1인지 확인합니다.
2. N100에 작은 Prometheus/Grafana를 배치하되 메모리 제한, PVC, 보존 기간/용량, 백업을 먼저 정합니다. 7일 보존을 초기 후보로 삼고 실제 디스크 사용으로 조정합니다.
3. blackbox HTTP probe 또는 전용 exporter로 Mac mini /api/tags 도달성을 수집합니다. Ollama가 Prometheus /metrics를 기본 제공한다고 가정하지 않습니다.
4. 향후 backend에 요청 지연·오류·대기열·토큰 지표를 추가합니다. 모델 생성 probe는 낮은 주기로 분리해 실제 추론 가능성을 확인합니다.

| 계층 | 관측 항목 | 초기 알림 후보 / 대응 |
|---|---|---|
| K3s/Linux | Ready, CPU, RAM, disk, Pod restart | NotReady 5분: 노드/네트워크 점검 |
| 저장소 | 사용량, 백업 나이, 복원 결과 | 디스크 80% 지속: retention/데이터 증가 확인 |
| Mac mini | 가용 메모리, memory pressure, 절전, 서버 로그 | API probe 3회 실패: 전원/프로세스/bind 확인 |
| API | 요청 수, 5xx, timeout, p50/p95, TTFT | 오류율 5%/5분은 후보, 최소 요청 수와 함께 조정 |
| 모델 | cold/warm 지연, output tokens/s, 동시성 | 동일 조건 기준선 대비 악화 확인 |

macOS 자원 지표는 macOS 지원 수집기를 별도 선정합니다. Linux node-exporter DaemonSet이 Mac mini를 감시하지 않습니다. TTFT는 streaming 첫 토큰을 계측해야 하며 non-stream 전체 지연과 구분합니다. label에 prompt/user ID를 넣지 않습니다.

## 장애·백업 연습

Mac mini 중단 시 앱이 제한 시간 안에 실패하고 무한 큐가 생기지 않는지 확인합니다. N5095 중단 시 앱/PVC의 복구 한계를 기록합니다. N100 단일 server의 datastore 형식을 확인해 해당 K3s 공식 백업 절차를 적용하고 토큰도 안전하게 보관합니다. SQLite와 embedded etcd의 백업 절차를 혼용하지 않습니다.

대시보드 스크린샷과 알림/복구 시간을 확보하기 전에는 운영 검증 완료로 표시하지 않습니다.
