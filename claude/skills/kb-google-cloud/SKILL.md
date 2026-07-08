---
name: kb-google-cloud
description: Google Cloud（GCP）のナレッジ。アカウント構成、gcloud CLI、Vertex AI、ADK、Agent Engine等
user-invocable: true
model: sonnet
---

# Google Cloud ナレッジ

みのるんの Google Cloud アカウント構成、よく使うコマンド、Vertex AI / ADK に関する学びを記録する。

---

## gcloud CLI セットアップ

### インストール
```bash
brew install --cask google-cloud-sdk
```

- **インストール先**: `/opt/homebrew/share/google-cloud-sdk/`
- **バージョン**: 560.0.0（2026-03-11 インストール）

### PATH 設定（~/.zshrc に追加）
```bash
source /opt/homebrew/share/google-cloud-sdk/path.zsh.inc
source /opt/homebrew/share/google-cloud-sdk/completion.zsh.inc
```

### 認証
```bash
# CLI 認証（ブラウザ）
gcloud auth login

# アプリ用認証（ADC）
gcloud auth application-default login

# 認証確認
gcloud auth list
```

### プロジェクト設定
```bash
gcloud config set project <PROJECT_ID>
gcloud config get project
gcloud projects list
```

### API 有効化
```bash
# Vertex AI API
gcloud services enable aiplatform.googleapis.com --project=<PROJECT_ID>

# Agent Engine 用（追加で必要な場合）
gcloud services enable agentengines.googleapis.com --project=<PROJECT_ID>
```

---

## Vertex AI / ADK

### Google ADK（Agent Development Kit）とは
- Google が提供する AI エージェント開発フレームワーク
- AWS の Strands Agents に相当するもの
- ローカルで動かして Vertex AI Agent Engine にデプロイできる

### インストール
```bash
uv add google-adk
# または
pip install google-adk
```

### Vertex AI Agent Engine とは
- Google が提供するサーバーレスエージェント実行環境
- AWS の Bedrock AgentCore Runtime に相当するもの
- ADK で作ったエージェントをデプロイして API として公開できる

### 主要リージョン
- `us-central1`（Agent Engine の主要リージョン、最も機能が揃っている）

### よく使う環境変数
```bash
GOOGLE_CLOUD_PROJECT=<プロジェクトID>
GOOGLE_CLOUD_REGION=us-central1
GOOGLE_CLOUD_LOCATION=us-central1
```

### ADK エージェントのローカル開発

#### ディレクトリ構成（必須）

```
<プロジェクトルート>/       ← ここで `uv run adk web` を実行
└── <エージェント名>/       ← Pythonパッケージ（このフォルダ名 = エージェント名）
    ├── __init__.py         ← 必須（`from . import agent` の1行でOK）
    ├── agent.py            ← `root_agent` を定義
    └── .env                ← GOOGLE_CLOUD_PROJECT, GOOGLE_CLOUD_LOCATION
```

#### ローカル起動
```bash
# カレントディレクトリ = エージェントパッケージの親ディレクトリ
uv run adk web --port 8080
```

**NG**: `uv run adk web hello_agent` のように引数を渡すと UI がエージェントを検出できない場合がある。引数なしで実行すること。

#### 最小エージェント実装

```python
# agent.py
from google.adk.agents import Agent

def my_tool(param: str) -> dict:
    """ツールの説明。docstringが必須（LLMへのツール説明に使われる）"""
    return {"result": param}

root_agent = Agent(
    name="my_agent",
    model="gemini-2.0-flash",
    description="エージェントの説明",
    instruction="ユーザーへの指示",
    tools=[my_tool],
)
```

### Vertex AI Agent Engine へのデプロイ

#### デプロイに必要なファイル構成

```
<プロジェクトルート>/
├── pyproject.toml          ← google-adk を依存に含める
├── .env                    ← GOOGLE_CLOUD_PROJECT, GOOGLE_CLOUD_LOCATION
└── <エージェント名>/
    ├── __init__.py         ← 必須: `from . import agent`（これがないとデプロイ失敗）
    └── agent.py            ← root_agent を定義
```

#### デプロイコマンド

```bash
# uvプロジェクトルートで実行
uv run adk deploy agent_engine \
    --project=<PROJECT_ID> \
    --region=us-central1 \
    --display_name="my-agent" \
    <エージェント名>
```

#### 主要オプション

| オプション | 説明 |
|-----------|------|
| `AGENT`（引数） | デプロイするエージェントのディレクトリ名 |
| `--project` | GCPプロジェクトID |
| `--region` | リージョン |
| `--display_name` | Agent Engine上の表示名 |
| `--agent_engine_id` | 既存インスタンスを**更新**する場合のID（未指定=新規作成） |

デプロイ成功時の出力例:
```
✅ Created agent engine: projects/<PROJECT_NUM>/locations/us-central1/reasoningEngines/<RESOURCE_ID>
```

#### デプロイ済みエージェントの呼び出し（Python SDK）

```python
import asyncio
import vertexai

client = vertexai.Client(project="<PROJECT_ID>", location="us-central1")

adk_app = client.agent_engines.get(
    name="projects/<PROJECT_NUM>/locations/us-central1/reasoningEngines/<RESOURCE_ID>"
)

async def main():
    session = await adk_app.async_create_session(user_id="user_001")
    async for event in adk_app.async_stream_query(
        user_id="user_001",
        session_id=session["id"],
        message="こんにちは！",
    ):
        print(event)

asyncio.run(main())
```

必要パッケージ: `google-cloud-aiplatform[agent_engines,adk]>=1.112`

---

## ハマりポイント・トラブルシューティング

### gcloud が PATH に見つからない（Homebrew インストール後）

**症状**: ターミナルを新規起動すると `gcloud: command not found`

**原因**: Homebrew cask インストール後、PATH が自動設定されない

**解決策**: `~/.zshrc` に以下を追加
```bash
source /opt/homebrew/share/google-cloud-sdk/path.zsh.inc
source /opt/homebrew/share/google-cloud-sdk/completion.zsh.inc
```

### Python バージョン警告

**症状**: `WARNING: Python 3.9.x is no longer officially supported`

**原因**: Homebrew の `gcloud-cli` が Python 3.9 を参照している

**解決策**: `CLOUDSDK_PYTHON` 環境変数で Python 3.13 を指定
```bash
export CLOUDSDK_PYTHON=/opt/homebrew/bin/python3.13
```

### ADC Quota Project 警告

**症状**: `Cannot find a quota project to add to ADC. You might receive a "quota exceeded" error.`

**解決策**:
```bash
gcloud auth application-default set-quota-project <PROJECT_ID>
```

### gcloud プロジェクトIDの重複エラー

**症状**: `gcloud projects create <name>` で `The project ID you specified is already in use`

**原因**: GCPのプロジェクトIDはグローバルユニーク（全ユーザー共通の名前空間）

**解決策**: ユーザー名などのサフィックスを付けてユニークにする（例: `my-project-minorun365`）

### `gcloud config set compute/region` 実行時にAPIの有効化を求められる

**症状**: region 設定時に Compute Engine API の有効化プロンプトが表示される

**対処**: N を選択してスキップしても region は設定される（`WARNING: Property validation for compute/region was skipped.` と出るが問題なし）

### `adk web` のポート競合

**症状**: `error while attempting to bind on address ('127.0.0.1', 8000): address already in use`

**原因**: デフォルトポート 8000 が他プロセスに使用中（workspace-mcp 等も 8000 を使う）

**解決策**: `--port` オプションで別ポートを指定
```bash
uv run adk web --port 8080
```

`get_fast_api_app` でサーバーを立てる場合も **8001 など別ポートを使うこと**。`lsof -i :8000` で競合プロセスを確認できる。

### `get_fast_api_app` で Vertex AI が使われず API キーエラーになる

**症状**: `No API key was provided.` エラー

**原因**: `GOOGLE_GENAI_USE_VERTEXAI=1` が未設定だと Gemini API（API キー必須）にフォールバックする

**解決策**: `.env` に追加
```
GOOGLE_GENAI_USE_VERTEXAI=1
```

### `uv init` がサブ Git リポジトリを作成する

**症状**: `uv init` 実行後に `.git/` が作成され、モノレポ内でネストしたリポジトリになる

**解決策**: 作成された `.git/`、`main.py`、`README.md` を削除
```bash
rm -rf .git main.py README.md
```
