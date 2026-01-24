# Python開発ツール ナレッジ

Python開発で使用するツールの学びを記録する。

## uv（パッケージマネージャー）

### 概要
- Rustで書かれた高速なPythonパッケージマネージャー
- pip/venv/pyenvの代替
- 公式: https://docs.astral.sh/uv/

### 基本コマンド
```bash
# プロジェクト初期化
uv init --no-workspace

# 依存追加
uv add strands-agents bedrock-agentcore

# スクリプト実行
uv run python script.py

# 仮想環境の場所
# .venv/ がプロジェクトルートに作成される
```

### AWS CLI login 認証を使う場合
```bash
uv add 'botocore[crt]'
```
`aws login` で認証した場合、botocore[crt] が必要。これがないと認証エラーになる。

### requirements.txt との併用
```bash
# requirements.txt から依存をインストール
uv pip install -r requirements.txt

# pyproject.toml に同期
uv add $(cat requirements.txt | tr '\n' ' ')
```

## Strands Agents

### 基本構造
```python
from strands import Agent

agent = Agent(
    model="us.anthropic.claude-sonnet-4-5-20250929-v1:0",
    system_prompt="あなたはアシスタントです",
)
```

### ストリーミング
```python
async for event in agent.stream_async(prompt):
    if "data" in event:
        print(event["data"], end="", flush=True)
```

### イベントタイプ
- `data`: テキストチャンク
- `current_tool_use`: ツール使用情報
- `result`: 最終結果

## Bedrock AgentCore SDK

### 基本構造
```python
from bedrock_agentcore import BedrockAgentCoreApp
from strands import Agent

app = BedrockAgentCoreApp()
agent = Agent(model="us.anthropic.claude-sonnet-4-5-20250929-v1:0")

@app.entrypoint
async def invoke(payload):
    prompt = payload.get("prompt", "")
    stream = agent.stream_async(prompt)
    async for event in stream:
        yield event

if __name__ == "__main__":
    app.run()  # ポート8080でリッスン
```

### エンドポイント
- `POST /invocations` - エージェント実行
- `GET /ping` - ヘルスチェック

### Dockerfileの例
```dockerfile
FROM python:3.12-slim

WORKDIR /app

# システム依存（Marp CLI用のChromium等）
RUN apt-get update && apt-get install -y \
    chromium \
    && rm -rf /var/lib/apt/lists/*

# Python依存
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# AgentCore SDKはポート8080を使用
EXPOSE 8080
CMD ["python", "agent.py"]
```

### 環境変数（Chromium用）
```dockerfile
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
```
