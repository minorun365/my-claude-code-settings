---
name: kb-strands-agentcore
description: Strands Agents + Bedrock AgentCore のナレッジ。エージェント開発、ツール定義、CDK、Observability等
user-invocable: true
---

# Strands Agents + AgentCore ナレッジ

AWS が提供する AI エージェントフレームワーク「Strands Agents」とサーバーレスランタイム「Bedrock AgentCore」に関する学びを記録する。

## 基本情報

### Strands Agents
- 公式: https://strandsagents.com/
- GitHub: https://github.com/strands-agents/strands-agents
- Python 3.10以上が必要

### Bedrock AgentCore
- 15リージョンで利用可能（us-east-1, us-west-2, ap-northeast-1 等）
- Evaluations機能のみ一部リージョン限定（東京は非対応）

## インストール

```bash
# pip
pip install strands-agents bedrock-agentcore

# uv
uv add strands-agents bedrock-agentcore
```

### AWS CLI login 認証を使う場合
```bash
uv add 'botocore[crt]'
```
`aws login` で認証した場合、botocore[crt] が必要。これがないと認証エラーになる。

### Observability（トレース）対応

AgentCore Observability でトレースを出力する場合、以下の4点が必要：

1. **requirements.txt**
```
strands-agents[otel]
aws-opentelemetry-distro
```

2. **Dockerfile**（`opentelemetry-instrument` で起動）
```dockerfile
CMD ["opentelemetry-instrument", "python", "agent.py"]
```

3. **CDK環境変数**
```typescript
environmentVariables: {
  AGENT_OBSERVABILITY_ENABLED: 'true',
  OTEL_PYTHON_DISTRO: 'aws_distro',
  OTEL_PYTHON_CONFIGURATOR: 'aws_configurator',
  OTEL_EXPORTER_OTLP_PROTOCOL: 'http/protobuf',
}
```

4. **import パス**（トップレベルから import すること）
```python
# OK: トレースが出力される
from bedrock_agentcore import BedrockAgentCoreApp

# NG: トレースが出力されない（ログ・メトリクスは出るがトレースだけ欠落）
from bedrock_agentcore.runtime import BedrockAgentCoreApp
```

**注意**: 上記4つすべてが必要。1つでも欠けるとトレースが出力されない。

### import パスの罠: runtime サブモジュール経由だとトレースが出ない

`from bedrock_agentcore.runtime import BedrockAgentCoreApp` を使うと、内部的には同じクラスが動くにもかかわらず、GenAI Observability の Traces View にトレースが一切表示されない。OTel のログ・メトリクスは正常に出力されるため、影響を受けるのはトレース（X-Ray スパン）のエクスポートのみ。SDK のトップレベル `__init__.py` での Observability 初期化フックに乗らないことが原因と推測される。

---

## Agent作成

### 基本構造
```python
from strands import Agent

agent = Agent(
    model="us.anthropic.claude-sonnet-4-5-20250929-v1:0",
    system_prompt="あなたはアシスタントです",
)
```

### 利用可能なモデル（Bedrock）

クロスリージョン推論のプレフィックスはリージョンによって異なる：

| リージョン | プレフィックス |
|-----------|--------------|
| us-east-1, us-west-2 | `us.` |
| ap-northeast-1（東京） | `jp.` |

```python
# リージョンに応じてプレフィックスを自動判定
import os

def _get_model_id() -> str:
    region = os.environ.get("AWS_REGION", "us-east-1")
    prefix = "jp" if region == "ap-northeast-1" else "us"
    return f"{prefix}.anthropic.claude-sonnet-4-5-20250929-v1:0"
```

---

## 実行方法

### 同期実行
```python
result = agent(prompt)
print(result)
```

### 非同期実行
```python
result = await agent.invoke_async(prompt)
```

### ストリーミング（同期）
```python
for event in agent.stream(prompt):
    if "data" in event:
        print(event["data"], end="", flush=True)
```

### ストリーミング（非同期）
```python
async for event in agent.stream_async(prompt):
    if "data" in event:
        print(event["data"], end="", flush=True)
```

---

## イベントタイプ

ストリーミング時に受け取るイベント：

| イベント | 説明 |
|---------|------|
| `data` | テキストチャンク（LLMの出力） |
| `current_tool_use` | ツール使用情報 |
| `result` | 最終結果 |

```python
async for event in agent.stream_async(prompt):
    if "data" in event:
        # テキストチャンク
        print(event["data"], end="")
    elif "current_tool_use" in event:
        # ツール使用中
        tool_info = event["current_tool_use"]
        print(f"Using tool: {tool_info['name']}")
    elif "result" in event:
        # 完了
        final_result = event["result"]
```

### ⚠️ current_tool_use の input はストリーミング中は文字列型

`current_tool_use` イベントの `input` フィールドは、ストリーミング中は**不完全なJSON文字列**として徐々に構築される。辞書型を期待している場合はJSONパースが必要：

```python
elif "current_tool_use" in event:
    tool_info = event["current_tool_use"]
    tool_name = tool_info.get("name", "unknown")
    tool_input = tool_info.get("input", {})

    # inputが文字列の場合はJSONパースを試みる
    if isinstance(tool_input, str):
        try:
            import json
            tool_input = json.loads(tool_input)
        except json.JSONDecodeError:
            pass  # パースできない場合はそのまま（不完全なJSON）

    # パース成功時のみ辞書として扱える
    if isinstance(tool_input, dict) and "query" in tool_input:
        print(f"Search query: {tool_input['query']}")
```

**ポイント**: ストリーミング中はイベントが複数回発火し、`{"query"` → `{"query": "検索` → `{"query": "検索ワード"}` のように徐々に完成する。完全なJSONになったタイミングでのみパースが成功する。

**⚠️ 重要**: フロントエンドにイベントを転送する場合、**必要なデータが取得できるまでイベントを送信しない**ことが重要。最初の「空のinput」でイベント送信すると、フロントエンドで不完全な状態が表示され、後から来る完全なデータが重複防止ロジックでスキップされる問題が起きる。

```python
# ❌ NG: クエリがなくてもイベント送信 → 空のステータスが先に表示される
if tool_name == "web_search" and isinstance(tool_input, dict) and "query" in tool_input:
    yield {"type": "tool_use", "data": tool_name, "query": tool_input["query"]}
else:
    yield {"type": "tool_use", "data": tool_name}  # ← これが先に送信される

# ✅ OK: web_searchはクエリ取得時のみ送信
if tool_name == "web_search":
    if isinstance(tool_input, dict) and "query" in tool_input:
        yield {"type": "tool_use", "data": tool_name, "query": tool_input["query"]}
    # クエリがない場合は送信しない（完全なJSONを待つ）
else:
    yield {"type": "tool_use", "data": tool_name}
```

---

## ツールの定義

### 関数デコレータ方式
```python
from strands import Agent, tool

@tool
def get_weather(city: str) -> str:
    """指定した都市の天気を取得します。

    Args:
        city: 都市名

    Returns:
        天気情報
    """
    return f"{city}の天気は晴れです"

agent = Agent(
    model="us.anthropic.claude-sonnet-4-5-20250929-v1:0",
    tools=[get_weather],
)
```

### クラス方式
```python
from strands import Agent, Tool

class WeatherTool(Tool):
    name = "get_weather"
    description = "指定した都市の天気を取得します"

    def run(self, city: str) -> str:
        return f"{city}の天気は晴れです"

agent = Agent(
    model="us.anthropic.claude-sonnet-4-5-20250929-v1:0",
    tools=[WeatherTool()],
)
```

### ツール駆動型の出力パターン

LLMの出力をフロントエンドでフィルタリングするのが難しい場合、出力専用のツールを作成してツール経由で出力させる方式が有効。

```python
# グローバル変数で出力を保持
_generated_markdown: str | None = None

@tool
def output_slide(markdown: str) -> str:
    """生成したスライドのマークダウンを出力します。

    Args:
        markdown: Marp形式のマークダウン全文

    Returns:
        出力完了メッセージ
    """
    global _generated_markdown
    _generated_markdown = markdown
    return "スライドを出力しました。"

agent = Agent(
    model="us.anthropic.claude-sonnet-4-5-20250929-v1:0",
    system_prompt="スライドを作成したら、必ず output_slide ツールを使って出力してください。",
    tools=[output_slide],
)
```

**メリット**:
- フロントエンドでのテキスト除去処理が不要
- ツール使用中のステータス表示が容易
- マークダウンがテキストストリームに混入しない

### 外部APIカスタムツール（追加パッケージ不要）

外部REST APIを呼ぶカスタムツールは `urllib.request`（標準ライブラリ）で実装すると、requirements.txtに追加パッケージ不要で済む。

```python
import json
import os
import urllib.request

from strands import tool

TAVILY_API_KEY = os.environ.get("TAVILY_API_KEY", "")

@tool
def web_search(query: str) -> str:
    """ウェブ検索を行い、最新の情報を取得します。

    Args:
        query: 検索クエリ

    Returns:
        検索結果のテキスト
    """
    req = urllib.request.Request(
        "https://api.tavily.com/search",
        data=json.dumps({
            "query": query,
            "max_results": 5,
            "search_depth": "basic",
            "include_answer": True,
        }).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {TAVILY_API_KEY}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    with urllib.request.urlopen(req, timeout=30) as resp:
        result = json.loads(resp.read().decode("utf-8"))

    parts = []
    if result.get("answer"):
        parts.append(f"【要約】\n{result['answer']}")
    for item in result.get("results", []):
        title = item.get("title", "")
        url = item.get("url", "")
        content = item.get("content", "")
        parts.append(f"■ {title}\n{url}\n{content}")

    return "\n\n".join(parts) if parts else "検索結果が見つかりませんでした。"
```

**ポイント**: `tavily-python` パッケージを使う方法もあるが、`urllib.request` なら追加依存なし。Docker/AgentCoreのビルド時間短縮にも有効。

---

## 会話履歴の管理

```python
from strands import Agent

agent = Agent(model="us.anthropic.claude-sonnet-4-5-20250929-v1:0")

# 会話を継続
response1 = agent("私の名前は太郎です")
response2 = agent("私の名前は何ですか？")  # 「太郎」と答える

# 履歴をクリア
agent.clear_history()
```

---

## Bedrock AgentCore との統合

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

### 必要な依存関係
```
# requirements.txt
bedrock-agentcore
strands-agents
tavily-python  # Web検索が必要な場合
```

**注意**: fastapi/uvicorn は不要（bedrock-agentcore SDKに内包）

### セッションIDでAgentを管理（複数ユーザー対応）

AgentCoreで複数ユーザーの会話履歴を保持する場合、セッションIDごとにAgentインスタンスを管理する：

```python
from strands import Agent

# セッションごとのAgentインスタンスを管理
_agent_sessions: dict[str, Agent] = {}

def get_or_create_agent(session_id: str | None) -> Agent:
    """セッションIDに対応するAgentを取得または作成"""
    # セッションIDがない場合は新規Agentを作成（履歴なし）
    if not session_id:
        return Agent(
            model="us.anthropic.claude-sonnet-4-5-20250929-v1:0",
            system_prompt="...",
            tools=[...],
        )

    # 既存のセッションがあればそのAgentを返す
    if session_id in _agent_sessions:
        return _agent_sessions[session_id]

    # 新規セッションの場合はAgentを作成して保存
    agent = Agent(
        model="us.anthropic.claude-sonnet-4-5-20250929-v1:0",
        system_prompt="...",
        tools=[...],
    )
    _agent_sessions[session_id] = agent
    return agent

@app.entrypoint
async def invoke(payload):
    session_id = payload.get("session_id")
    agent = get_or_create_agent(session_id)
    # ...
```

**注意**: コンテナ再起動でセッションは消える（メモリ管理）。永続化が必要な場合はDynamoDB等を検討。

### ツール使用イベント送信
```python
@app.entrypoint
async def invoke(payload):
    global _generated_markdown
    _generated_markdown = None

    stream = agent.stream_async(payload.get("prompt", ""))
    async for event in stream:
        if "data" in event:
            yield {"type": "text", "data": event["data"]}
        elif "current_tool_use" in event:
            tool_name = event["current_tool_use"].get("name", "unknown")
            yield {"type": "tool_use", "data": tool_name}

    if _generated_markdown:
        yield {"type": "markdown", "data": _generated_markdown}
```

---

## AgentCore CDK

### Runtime作成（推奨パターン）

```typescript
import * as agentcore from '@aws-cdk/aws-bedrock-agentcore-alpha';

const artifact = agentcore.AgentRuntimeArtifact.fromAsset(
  path.join(__dirname, 'runtime')
);

const runtime = new agentcore.Runtime(stack, 'MyRuntime', {
  runtimeName: 'my-agent',
  agentRuntimeArtifact: artifact,
  authorizerConfiguration: agentcore.RuntimeAuthorizerConfiguration.usingJWT(
    discoveryUrl,
    [clientId],  // allowedClients - client_idクレームを検証
  ),
});

// エンドポイントはDEFAULTを使用（addEndpoint不要）
```

### JWT認証（Cognito統合）

AgentCore RuntimeのJWT認証（`usingJWT`の`allowedClients`）は **`client_id`クレーム** を検証する。

| トークン種別 | クライアントIDの格納先 | AgentCore認証 |
|-------------|---------------------|--------------|
| IDトークン | `aud` クレーム | NG |
| アクセストークン | `client_id` クレーム | OK |

**結論**: Cognito + AgentCore 連携では**アクセストークン**を使用する。

```typescript
// フロントエンドでの実装例
const session = await fetchAuthSession();
const accessToken = session.tokens?.accessToken?.toString();  // IDトークンではなくアクセストークン
```

### IAM権限（Bedrockモデル呼び出し）

クロスリージョン推論（`us.anthropic.claude-*`形式のモデルID）を使用する場合、以下の両方のリソースへの権限が必要：

```typescript
runtime.addToRolePolicy(new iam.PolicyStatement({
  actions: [
    'bedrock:InvokeModel',
    'bedrock:InvokeModelWithResponseStream',
  ],
  resources: [
    'arn:aws:bedrock:*::foundation-model/*',      // 基盤モデル
    'arn:aws:bedrock:*:*:inference-profile/*',    // 推論プロファイル（クロスリージョン推論）
  ],
}));
```

`foundation-model/*` だけでは `AccessDeniedException` が発生する。

### 環境変数渡し

```typescript
const runtime = new agentcore.Runtime(stack, 'MyRuntime', {
  runtimeName: 'my-agent',
  agentRuntimeArtifact: artifact,
  environmentVariables: {
    TAVILY_API_KEY: process.env.TAVILY_API_KEY || '',
    OTHER_SECRET: process.env.OTHER_SECRET || '',
  },
});
```

sandbox起動時に環境変数を設定する必要がある：
```bash
export TAVILY_API_KEY=$(grep TAVILY_API_KEY .env | cut -d= -f2) && npx ampx sandbox
```

### DEFAULTエンドポイント

Runtime を作成すると **DEFAULT エンドポイントが自動的に作成される**。特別な理由がなければ `addEndpoint()` は不要。

```typescript
// NG: 不要なエンドポイントが増える
const endpoint = runtime.addEndpoint('my-endpoint');  // DEFAULT + my-endpoint の2つになる

// OK: DEFAULTエンドポイントを使う
// addEndpoint() を呼ばない → DEFAULTのみ
```

### SSEストリーミング

エンドポイントURL形式：
```
POST https://bedrock-agentcore.{region}.amazonaws.com/runtimes/{URLエンコードARN}/invocations?qualifier={endpointName}
```

**重要**: ARNは `encodeURIComponent()` で完全にURLエンコードする必要がある。

レスポンス形式：
```
data: {"type": "text", "data": "テキストチャンク"}
data: {"type": "tool_use", "data": "ツール名"}
data: {"type": "markdown", "data": "生成されたコンテンツ"}
data: {"type": "error", "error": "エラーメッセージ"}
data: [DONE]
```

イベントペイロードは `content` または `data` フィールドに格納される。両方に対応が必要：
```typescript
const textValue = event.content || event.data;
```

---

## Observability（OTELログ）

### OTELログ形式

OTEL有効時、ログは `otel-rt-logs` ストリームにJSON形式で出力される。各セッションは `session.id` フィールドで識別される。

```json
{
  "resource": { ... },
  "scope": { "name": "strands.telemetry.tracer" },
  "timeUnixNano": 1769681571307833653,
  "body": {
    "input": { "messages": [...] },
    "output": { "messages": [...] }
  },
  "attributes": {
    "session.id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
  }
}
```

### CloudWatch Logs Insightsでのセッションカウント

OTELログからセッション数をカウントするクエリ：

```
parse @message /"session\.id":\s*"(?<sid>[^"]+)"/
| filter ispresent(sid)
| stats count_distinct(sid) as sessions by datefloor(@timestamp, 1h) as hour_utc
| sort hour_utc asc
```

**注意**: `datefloor(@timestamp + 9h, ...)` を使うと挙動が不安定。UTCで集計してからスクリプト側でJSTに変換する。

```bash
# UTCの時刻をJSTに変換
JST_HOUR=$(( (10#$UTC_HOUR + 9) % 24 ))
```

### トレースの確認

1. CloudWatch Console → **Bedrock AgentCore GenAI Observability**
2. Agents View / Sessions View / Traces View で確認可能

---

## Dockerfileの例

```dockerfile
FROM python:3.12-slim

WORKDIR /app

# システム依存（Marp CLI用のChromium等）
RUN apt-get update && apt-get install -y --no-install-recommends \
    chromium \
    fonts-noto-cjk \
    && rm -rf /var/lib/apt/lists/* \
    && fc-cache -fv

# Python依存
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# AgentCore SDKはポート8080を使用
EXPOSE 8080

# Chromium設定
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true

# OTELの自動計装を有効にして起動
CMD ["opentelemetry-instrument", "python", "agent.py"]
```

---

## FPDF2でPDF生成（日本語対応）

### 日本語フォント（NotoSansCJKjp）

日本語PDFを生成する場合、CJKフォントが必要。NotoSansCJKjpを使用：

```dockerfile
# Dockerfile: フォントをプロジェクトからコピー
COPY fonts/ /app/fonts/
```

**フォントの入手先**:
- https://github.com/minoryorg/Noto-Sans-CJK-JP
- `fonts/NotoSansCJKjp-Regular.ttf`
- `fonts/NotoSansCJKjp-Bold.ttf`

```python
# agent.py: FPDF2でフォント登録
from fpdf import FPDF

class MyPDF(FPDF):
    def __init__(self):
        super().__init__()
        self.add_font("NotoSansCJKjp", fname="/app/fonts/NotoSansCJKjp-Regular.ttf")
        self.add_font("NotoSansCJKjp", style="B", fname="/app/fonts/NotoSansCJKjp-Bold.ttf")
```

### S3への保存と署名付きURL

```python
from botocore.config import Config

# 署名付きURL用のクライアント（s3v4必須）
s3_presigned = boto3.client(
    "s3",
    region_name=AWS_REGION,
    config=Config(signature_version="s3v4"),
)

# PDFをS3にアップロード
pdf_bytes = pdf.output()
s3_client.put_object(
    Bucket=UPLOAD_BUCKET,
    Key=f"estimates/{estimate_no}.pdf",
    Body=pdf_bytes,
    ContentType="application/pdf",
)

# 署名付きURL生成（1時間有効）
download_url = s3_presigned.generate_presigned_url(
    ClientMethod="get_object",
    Params={"Bucket": UPLOAD_BUCKET, "Key": s3_key},
    ExpiresIn=3600,
)
```

### 注意点
- GitHubからフォントをcurlでダウンロードする場合、`-L`オプション必須（リダイレクト対応）
- apt-getでfonts-noto-cjkをインストールするとTTC形式になりFPDF2で追加設定が必要
- **プロジェクトにフォントファイルを含めてCOPYするのが最も確実**

---

## 外部APIキーの複数フォールバックパターン

レートリミットのある外部API（Tavily等）を使う場合、複数のAPIキーを環境変数に設定し、エラー時に自動で次のキーに切り替える方式が有効。

```python
from tavily import TavilyClient

# 複数キーでクライアント初期化
_clients: list[TavilyClient] = []
for key_name in ["TAVILY_API_KEY", "TAVILY_API_KEY2", "TAVILY_API_KEY3"]:
    key = os.environ.get(key_name, "")
    if key:
        _clients.append(TavilyClient(api_key=key))

# エラー時にフォールバック
def search_with_fallback(query: str) -> str:
    for client in _clients:
        try:
            return client.search(query=query)
        except Exception as e:
            error_str = str(e).lower()
            if "rate limit" in error_str or "429" in error_str or "usage limit" in error_str:
                continue  # 次のキーで再試行
            raise  # レートリミット以外はそのまま例外
    return "すべてのAPIキーが枯渇しました"
```

---

## 未リリースモデルの先行対応

### モデルID設定の先行追加

Bedrockでまだリリースされていないモデルでも、モデルIDを先に設定しておくことが可能。リリース時にコード変更なしで利用開始できる。

```python
def _get_model_config(model_type: str = "claude") -> dict:
    if model_type == "claude5":
        # Claude Sonnet 5（2026年リリース予定）
        # リリース前はエラーになるが、フロントエンドでユーザーに通知
        return {
            "model_id": "us.anthropic.claude-sonnet-5-20260203-v1:0",
            "cache_prompt": "default",
            "cache_tools": "default",
        }
    elif model_type == "kimi":
        return {"model_id": "moonshot.kimi-k2-thinking", "cache_prompt": None}
    else:
        return {"model_id": "us.anthropic.claude-sonnet-4-5-20250929-v1:0", "cache_prompt": "default"}
```

### 未リリース時のエラーハンドリング

モデルがBedrockで認識できない場合、以下のエラーが返される：

```
ValidationException: The provided model identifier is invalid.
```

フロントエンドでこのエラーを検出し、ユーザーフレンドリーなメッセージを表示：

```typescript
// onErrorコールバック内
onError: (error) => {
  const errorMessage = error instanceof Error ? error.message : String(error);
  const isModelNotAvailable = errorMessage.includes('model identifier is invalid');

  if (isModelNotAvailable) {
    // 疑似ストリーミングでユーザーに通知
    streamMessage('Claude Sonnet 5はまだリリースされていません。Bedrockへのモデル追加をお待ちください！');
  } else {
    streamMessage('エラーが発生しました。もう一度お試しください。');
  }
}
```

### 新モデル追加時のチェックリスト

| ファイル | 修正内容 |
|---------|---------|
| `agent.py` | `_get_model_config()` に新モデルの設定を追加 |
| `Chat.tsx` | `ModelType` 型に追加、セレクター選択肢を追加 |
| `useAgentCore.ts` | `ModelType` 型に追加（共通型定義の場合） |

---

## コンテナライフサイクルと環境変数

### コンテナはセッション単位でキャッシュされる

AgentCore Runtime は `runtimeSessionId` ごとにコンテナをルーティングする。同じセッションIDで呼び出すと同じコンテナが再利用される。

- デフォルトのアイドルタイムアウト: 900秒（15分）
- デフォルトの最大ライフタイム: 28800秒（8時間）

### CDK デプロイしてもコンテナはすぐに入れ替わらない

`npx cdk deploy` でコード・環境変数を更新しても、**既存の実行中コンテナは古いコード＆環境変数のまま動き続ける**。新しい設定が反映されるのは新規に起動されるコンテナのみ。

**対処法**: `stop-runtime-session` で既存セッションを停止

```bash
aws bedrock-agentcore stop-runtime-session \
  --runtime-session-id "セッションID" \
  --agent-runtime-arn "arn:aws:bedrock-agentcore:REGION:ACCOUNT:runtime/RUNTIME_NAME" \
  --qualifier DEFAULT \
  --region REGION
```

次回の呼び出し時に新しいコンテナが起動し、最新のコード・環境変数が反映される。セッション停止後は会話履歴（エージェント内のメモリ）もリセットされる。

---

## ツール単位のアクセス制御パターン

特定のツールだけを許可されたユーザーに制限し、他のツールは誰でも使えるようにする方式。

### 実装パターン

1. **呼び出し元からペイロードに `user_id` を含める**
2. **エージェント側で `ALLOWED_USER_IDS` 環境変数を読み込む**（モジュールレベル、コンテナ起動時に1回）
3. **制限対象のツール内でユーザーIDを照合**し、不一致なら拒否メッセージを返す

```python
ALLOWED_USER_IDS = set(
    uid.strip()
    for uid in os.environ.get("ALLOWED_USER_IDS", "").split(",")
    if uid.strip()
)
_current_user_id: str | None = None

@tool
def restricted_tool() -> str:
    """許可されたユーザーのみ使用可能なツール"""
    if ALLOWED_USER_IDS and _current_user_id not in ALLOWED_USER_IDS:
        return "この機能は許可されたユーザーのみ利用できます。"
    # ... 本来の処理

@app.entrypoint
async def invoke_agent(payload, context):
    global _current_user_id
    _current_user_id = payload.get("user_id")
    # ...
```

**ポイント**:
- 空の `ALLOWED_USER_IDS`（= 未設定）の場合は全員許可（`if ALLOWED_USER_IDS and ...`）
- `ALLOWED_USER_IDS` はモジュールレベルで読み込まれるため、変更時はセッション停止が必要

---

## LLM にやらせてはいけない計算

### 日付→曜日の変換

LLM は日付から曜日を計算するのが苦手（既知の弱点）。`strands_tools` の `current_time` は ISO 8601 形式（例: `2026-02-09T02:46:56+00:00`）を返すが、曜日情報が含まれないため LLM が誤認識する。

**実例**: 2026年2月9日（月曜日）を LLM が「日曜日」と誤認識

**原則**: LLM に計算させず、ツール側で確定情報を返す。

```python
from datetime import datetime, timezone, timedelta
from strands import tool

JST = timezone(timedelta(hours=9))
WEEKDAY_JA = ["月", "火", "水", "木", "金", "土", "日"]

@tool
def current_time() -> str:
    """現在の日本時間（JST）を曜日付きで取得します。"""
    now = datetime.now(JST)
    weekday = WEEKDAY_JA[now.weekday()]
    return f"{now.year}年{now.month}月{now.day}日({weekday}) {now.strftime('%H:%M')} JST"
```

**ポイント**:
- タイムゾーン変換もツール側で完結させる（システムプロンプトの「+9時間して」は不確実）
- `Python の weekday()` は月曜=0 なので日本語曜日配列のインデックスと一致する
- `strands_tools.current_time` の代わりにカスタムツールを使う

---

## トラブルシューティング

### AWS認証エラー
`aws login` で認証した場合、`botocore[crt]` が必要：
```bash
uv add 'botocore[crt]'
```

### モデルが見つからない
クロスリージョン推論のモデルID（`us.` プレフィックス）を使用しているか確認。
リージョンによって利用可能なモデルが異なる。

### ストリーミングが動かない
`stream()` と `stream_async()` を環境に合わせて使い分ける：
- 同期コンテキスト → `stream()`
- 非同期コンテキスト（async/await） → `stream_async()`

### Kimi K2関連

Kimi K2（Moonshot AI）特有の問題は `/kb-kimi` スキルを参照してください。

---

## 参考リンク

- [Strands Agents 公式ドキュメント](https://strandsagents.com/)
- [GitHub リポジトリ](https://github.com/strands-agents/strands-agents)
- [Bedrock AgentCore 統合ガイド](https://docs.aws.amazon.com/bedrock/latest/userguide/agents-agentcore.html)
