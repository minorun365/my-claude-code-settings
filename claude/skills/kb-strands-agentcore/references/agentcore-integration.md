# Bedrock AgentCore との統合

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

### SSE keep-alive パターン（長時間処理のコネクション維持）

同期的な重い処理（ファイル変換、外部API呼び出し等）をSSEで返す場合、処理中にkeep-aliveイベントを送信してコネクションを維持する。`asyncio.run_in_executor` + `asyncio.shield` + タイムアウトの組み合わせ。

```python
import asyncio

async def _wait_with_keepalive(task, format_name):
    """タスク完了を待ちつつ、5秒ごとにSSE keep-aliveイベントをyield"""
    while not task.done():
        try:
            await asyncio.wait_for(asyncio.shield(task), timeout=5.0)
        except asyncio.TimeoutError:
            yield {"type": "progress", "message": f"{format_name}変換中..."}

@app.entrypoint
async def invoke(payload, context=None):
    if action == "export_pptx" and markdown:
        try:
            print(f"[INFO] PPTX export started")
            loop = asyncio.get_event_loop()
            task = loop.run_in_executor(None, generate_pptx, markdown, theme)
            async for event in _wait_with_keepalive(task, "PPTX"):
                yield event  # 5秒ごとにprogressイベント送信
            result_bytes = task.result()
            yield {"type": "pptx", "data": base64.b64encode(result_bytes).decode()}
        except Exception as e:
            print(f"[ERROR] PPTX export failed: {e}")
            yield {"type": "error", "message": str(e)}
        return
```

**ポイント**:
- `asyncio.shield(task)` で TimeoutError 時もタスクがキャンセルされない
- `task.done()` でループ脱出を判定、`task.result()` で結果取得
- フロントエンドのSSEパーサーは未知の `type` を無視するため、既存コードの変更不要

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

## Bedrockプロンプトキャッシュが突然停止する

**症状**: Cost ExplorerのCacheWrite/CacheRead費用が特定のコミット以降ずっと0になる

**原因**: Bedrockのprompt cachingは**ツール定義の合計トークンが1024以上**必要。ツールのdocstringを短くしたり、リッチなビルトインツール（`strands_tools.http_request` 等）をシンプルなカスタムツールに置き換えると、合計が1024を割り込んでキャッシュが機能停止する。

| 状態 | http_requestのトークン数 | ツール合計 | キャッシュ |
|------|------------------------|-----------|----------|
| strands_tools版（21パラメータ） | ~884 tokens | ~1096 | 動作 |
| カスタム版（2パラメータ、docstring短い） | ~90 tokens | ~302 | 停止 |

**診断方法**:
1. Cost Explorerでモデル別にCacheWrite/CacheReadを確認し、0になり始めた日付を特定
2. その日付のコミットで `@tool` 付き関数のdocstringが短くなっていないか確認

**解決策**: docstringを拡充して合計1024トークン以上に戻す（パラメータの詳細説明・使用例・注意事項を追加すると大幅に増やせる）

**`@tool` デコレータとトークン数の関係**:
- Strands Agentsの `@tool` デコレータはPython関数のdocstringをBedrockへのツール説明（tool spec）として送信する
- パラメータ数・docstringの文字数がそのまま毎リクエストのトークンコストになる
- docstringが増えてもキャッシュリード時は90%オフになるため、キャッシュが有効な状態では長いdocstringでもコスト増にはならない

**Bedrockキャッシュの課金構造（Sonnet 4.6）**:
| 種別 | 単価 | 備考 |
|------|------|------|
| 通常インプット | $3.00/MTok | キャッシュなし時 |
| キャッシュライト | $3.75/MTok | 初回（25%高い） |
| キャッシュリード | $0.30/MTok | 2回目以降（**90%オフ**） |

---

