# K3s → Mac mini 로컬 LLM 통합

## 연결 방식

selector 없는 ClusterIP Service와 수동 EndpointSlice로 외부 Mac mini를 가리킵니다. 앱은 http://ollama.keun-federation.svc.cluster.local:11434를 사용합니다. Pod나 Ollama Deployment를 생성하지 않습니다. namespace와 Service는 기존 이름을 유지합니다.

[공식 Service 문서](https://kubernetes.io/docs/concepts/services-networking/service/)의 selector 없는 Service/EndpointSlice 방식입니다. API 서버 프록시를 통한 kubectl port-forward 대신 Pod에서 직접 호출합니다.

## 적용

저장소 루트에서 실행합니다. MAC_MINI_LAN_IP는 실제 고정 IPv4로 교체합니다. 기존 v1 Endpoints가 있다면 먼저 그 YAML을 안전한 로컬 경로에 백업합니다.

```bash
kubectl apply -f manifests/namespace.yaml
export MAC_MINI_LAN_IP='<실제-Mac-mini-IPv4>'
sed "s/MAC_MINI_LAN_IP/$MAC_MINI_LAN_IP/g" \
  manifests/ollama/ollama-service.yaml > /tmp/mac-mini-ollama.yaml
kubectl apply --dry-run=server -f /tmp/mac-mini-ollama.yaml
# v1 수동 Endpoints가 존재할 때만 제거: 같은 Service에 구/신 대상 혼용 방지
kubectl -n keun-federation delete endpoints ollama --ignore-not-found
kubectl apply -f /tmp/mac-mini-ollama.yaml
kubectl -n keun-federation get service ollama
kubectl -n keun-federation get endpointslice -l kubernetes.io/service-name=ollama -o wide
```

수동 slice는 Mac mini IP 변경을 자동 추적하지 않습니다. 주소 변경 시 다시 적용합니다. Service의 selector는 비워둡니다.

## N5095 Pod에서 검증

승인된 curl 이미지를 선택해 CURL_IMAGE에 태그 또는 digest를 지정합니다. 실행 환경의 이미지 정책을 따릅니다.

```bash
export CURL_IMAGE='<승인한-curl-이미지:태그-또는-digest>'
kubectl run llm-smoke -n keun-federation --rm -i --restart=Never \
  --image="$CURL_IMAGE" \
  --overrides='{"spec":{"nodeSelector":{"workload":"apps"}}}' -- \
  --fail --connect-timeout 3 --max-time 120 \
  http://ollama.keun-federation.svc.cluster.local:11434/api/generate \
  -H 'Content-Type: application/json' \
  -d '{"model":"llama3.2:3b","prompt":"한 단어로 응답하세요.","stream":false}'
```

Mac mini에 설치한 모델명과 맞춥니다. 종료 코드 0, JSON 응답 및 실제 텍스트를 확인하고 버전/시각/지연을 기록합니다. DNS 실패는 CoreDNS/Service 이름, 연결 거부는 bind/프로세스, timeout은 라우팅/방화벽, 모델 오류는 설치 모델부터 확인합니다. 노드 직접 호출과 Pod 호출을 비교하면 원본 SNAT·NetworkPolicy 문제를 좁힐 수 있습니다.

## 앱 계약과 실패 시험

앱 설정 LLM_BASE_URL에 위 Service URL을 넣습니다. Ollama native /api/generate와 OpenAI 호환 /v1 API를 혼동하지 않습니다. 연결 timeout, 전체 생성 deadline, 동시 요청 상한 및 요청 크기 제한을 설정합니다. overload/timeout은 명시적인 503/504로 변환하고 스트리밍 중복 생성이 생기지 않게 자동 재시도를 제한합니다.

Mac mini 프로세스 중지/네트워크 단절/없는 모델/동시 요청을 시험합니다. 클라이언트 취소 전파와 큐 길이 제한도 구현 시 확인합니다. 앱과 RAG backend 구현은 이 문서 변경에 포함되지 않습니다.
