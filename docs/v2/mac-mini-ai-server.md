# Mac mini M4 Pro AI 서버

## 초기 구성

유선 LAN, DHCP reservation, 여유 디스크, 전원·절전 정책을 확인합니다. macOS 버전, 칩, unified memory, Ollama 버전을 기록합니다. 48GB 여부는 실물 확인 전 확정하지 않습니다.

[공식 macOS 다운로드](https://ollama.com/download/mac)에서 Ollama를 설치합니다. 우선 localhost에서 실행하고 작은 모델 하나로 검증합니다. 예시 모델은 성능 권장이 아니며 메모리와 라이선스를 확인해 선택합니다.

```bash
ollama --version
ollama pull llama3.2:3b
curl --fail --max-time 10 http://127.0.0.1:11434/api/tags
ollama run llama3.2:3b '한국어로 한 문장만 답하세요.'
ollama ps
```

모델명·digest·양자화·context 설정, GPU 사용, cold/warm 지연과 메모리를 기록합니다. 모델 다운로드 크기만으로 실행 메모리를 예측하지 않습니다.

## LAN 제공

Ollama 앱을 완전히 종료한 뒤 실제 Mac mini LAN IP에 bind하도록 설정하고 다시 실행합니다.

```bash
launchctl setenv OLLAMA_HOST '<MAC_MINI_LAN_IP>:11434'
# Ollama 앱을 다시 실행
```

동일 포트의 별도 ollama serve 프로세스를 중복 실행하지 않습니다. 이 설정은 현재 로그인 세션 기준으로 검증하고, 재부팅/로그인 후에도 서비스와 환경 변수가 유지되는지 확인합니다. 무인 운영이 필요하면 별도 launchd 관리·로그 회전·재시작 정책을 검증한 뒤 도입합니다.

API를 열기 전에 호스트/네트워크 방화벽에서 노드의 실제 egress 원본만 허용합니다. 사설 IP bind만으로 LAN 접근제어가 완성되지는 않습니다. Ollama의 로컬 API를 인증 경계로 간주하지 말고, 다중 사용자·원격 접속에는 인증/TLS gateway를 설계합니다.

N100와 N5095에서 각각 다음을 확인합니다.

```bash
curl --fail --connect-timeout 3 --max-time 10 http://<MAC_MINI_LAN_IP>:11434/api/tags
```

## 운영 및 복구

재부팅 후 모델 호출, 로그인 없이 필요한 가용성, 화면 잠금/절전 중 호출을 시험합니다. 실패 시 전원/절전 → 프로세스 → bind IP → 방화벽 → 모델 로딩 순서로 점검합니다. 모델 재현을 위해 버전과 설정을 남기되 prompt와 사용자 문서를 로그에 기본 저장하지 않습니다.

LAN 제공을 중지하려면 앱 종료 후 launchctl unsetenv OLLAMA_HOST를 실행하고 앱을 재시작해 localhost로 복귀했는지 확인합니다.

환경 변수와 GPU 확인 방법: [Ollama 공식 FAQ](https://docs.ollama.com/faq). MLX/embedding/reranker는 향후 개별 실험이며 현재 설치 완료 항목이 아닙니다.
