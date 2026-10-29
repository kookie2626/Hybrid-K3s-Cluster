# Docker 설치 및 텔레그램 봇 만들기

## 배경

N100 서버를 세팅한 뒤, 서버를 활용하는 방법을 익히기 위해 Docker를 공부했습니다.
Docker를 배우고 나서 첫 번째 실습 프로젝트로 **텔레그램 봇**을 만들어 서버에서 24시간 운영해봤습니다.
이 경험이 이후 쿠버네티스(K3s) 클러스터 구축의 기초가 되었습니다.

---

## Docker 설치

### 1. 기존 패키지 제거

```bash
sudo apt remove -y docker docker-engine docker.io containerd runc
```

### 2. Docker 공식 저장소 추가

```bash
# 필수 패키지 설치
sudo apt update
sudo apt install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release

# Docker GPG 키 추가
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Docker 저장소 등록
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```

### 3. Docker Engine 설치

```bash
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

### 4. 현재 사용자를 docker 그룹에 추가 (sudo 없이 사용 가능)

```bash
sudo usermod -aG docker $USER
newgrp docker
```

### 5. 설치 확인

```bash
docker --version
docker run hello-world
```

---

## 텔레그램 봇 만들기

### 봇 토큰 발급

1. 텔레그램에서 [@BotFather](https://t.me/BotFather)를 검색합니다.
2. `/newbot` 명령어를 입력하고 안내에 따라 봇 이름과 사용자명을 설정합니다.
3. 발급된 **API 토큰**을 안전한 곳에 보관합니다.

### 프로젝트 구조

```
telegram-bot/
├── bot.py
├── requirements.txt
└── Dockerfile
```

### bot.py

```python
import logging
import os
from telegram import Update
from telegram.ext import ApplicationBuilder, CommandHandler, MessageHandler, filters, ContextTypes

logging.basicConfig(
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    level=logging.INFO,
)

BOT_TOKEN = os.environ.get("BOT_TOKEN")
if not BOT_TOKEN:
    raise ValueError("BOT_TOKEN 환경 변수가 설정되지 않았습니다. docker run -e BOT_TOKEN=... 형식으로 전달하세요.")


async def start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text("안녕하세요! 봇이 정상 동작 중입니다 🤖")


async def echo(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text(update.message.text)


def main() -> None:
    app = ApplicationBuilder().token(BOT_TOKEN).build()
    app.add_handler(CommandHandler("start", start))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, echo))
    app.run_polling()


if __name__ == "__main__":
    main()
```

### requirements.txt

```
# python-telegram-bot 최신 안정 버전 확인: https://pypi.org/project/python-telegram-bot/
python-telegram-bot==20.7
```

### Dockerfile

```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY bot.py .

CMD ["python", "bot.py"]
```

---

## Docker로 봇 실행

### 이미지 빌드

```bash
cd telegram-bot
docker build -t telegram-bot .
```

### 컨테이너 실행 (BOT_TOKEN 환경 변수 주입)

```bash
docker run -d \
  --name telegram-bot \
  --restart unless-stopped \
  -e BOT_TOKEN="여기에_발급받은_토큰_입력" \
  telegram-bot
```

- `-d` : 백그라운드(데몬) 모드로 실행
- `--restart unless-stopped` : 서버 재부팅 시 자동으로 컨테이너 재시작
- `-e BOT_TOKEN=...` : 토큰을 환경 변수로 전달 (소스 코드에 토큰을 직접 넣지 않음)

### 실행 상태 및 로그 확인

```bash
# 실행 중인 컨테이너 확인
docker ps

# 봇 로그 실시간 확인
docker logs -f telegram-bot
```

---

## docker compose로 관리하기

여러 서비스를 함께 운영할 때는 `docker-compose.yml`로 관리하면 편리합니다.

```yaml
services:
  telegram-bot:
    build: .
    container_name: telegram-bot
    restart: unless-stopped
    environment:
      - BOT_TOKEN=${BOT_TOKEN}
```

`.env` 파일에 토큰을 저장합니다 (`.gitignore`에 반드시 추가):

```
BOT_TOKEN=여기에_발급받은_토큰_입력
```

```bash
# 실행
docker compose up -d

# 중지
docker compose down
```

---

## 결과

N100 서버에서 텔레그램 봇이 24시간 안정적으로 동작하게 되었습니다.
Docker의 컨테이너 격리·이식성·자동 재시작 기능을 직접 체험하면서,
이후 쿠버네티스(K3s) 클러스터로 확장하는 데 필요한 개념적 기반을 쌓을 수 있었습니다.
