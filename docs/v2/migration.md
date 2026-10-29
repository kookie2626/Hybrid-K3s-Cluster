# v1 → v2 전환과 롤백

이 PR은 저장소 문서·예제만 변경합니다. 실제 노드를 drain/delete하거나 인프라를 재설치하지 않습니다.

## 전환 순서

1. 현재 노드, workload, PVC/PV, ingress, Service/Endpoints와 설치 버전을 기록합니다. kubeconfig·토큰·백업은 Git 밖에 보관합니다.
2. MacBook Pro/Lima에 있는 Pod와 local PV를 확인합니다. 데이터 복사와 복원 검증, 대체 노드 용량 확보 전 drain하지 않습니다.
3. N100/N5095 Ready 및 workload label을 확인하고 앱을 N5095로 재배치합니다. DaemonSet/PDB와 node affinity도 확인합니다.
4. Mac mini를 localhost → 노드 직접 호출 → K3s Service 호출 순으로 검증합니다. 기존 ollama Endpoints와 신규 EndpointSlice 전환은 통합 가이드를 따릅니다.
5. 앱의 정상 호출·장애 처리·모니터링 기준을 충족한 뒤에만 구형 노드를 한 대씩 퇴역합니다. drain/delete는 운영자가 데이터·PDB를 검토한 후 수행합니다.
6. 실제 완료 항목과 버전/검증 결과를 별도 기록합니다.

## 롤백

노드 퇴역 전까지 기존 환경을 유지합니다. 신규 Mac mini 연동 실패 시 앱 설정을 이전 검증 주소로 복구합니다. 동일 Service를 v1으로 되돌릴 때는 수동 EndpointSlice ollama-mac-mini를 삭제한 뒤 백업한 기존 Endpoints와 Service를 적용하고 Pod에서 호출을 재검증합니다. 구형 데이터가 삭제되었거나 OS가 재설치되었다면 문서만으로 복구되지 않으므로 검증된 백업 복원을 사용합니다.

## 기록 보존

legacy/에는 전환 전 README·docs·scripts·manifests를 함께 보존해 당시 상대 링크를 유지합니다. 기존 구형 장비 문서 경로는 legacy로 안내합니다. 기존 일반 Linux 설치 문서와 스크립트도 v1 가정이 포함되어 있으므로 v2 자동화로 오해하지 않도록 안내를 추가했습니다.
