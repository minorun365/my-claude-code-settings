# Bedrock AgentCore runtime integration

## 目次

- Bedrock AgentCore との統合
  - 基本構造
  - エンドポイント
  - 必要な依存関係
  - import パスの罠: runtime サブモジュール経由だとトレースが出ない
  - セッションIDでAgentを管理（複数ユーザー対応）
  - SSE keep-alive パターン（長時間処理のコネクション維持）
  - ツール使用イベント送信

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

### import パスの罠: runtime サブモジュール経由だとトレースが出ない

```python
# OK: トレースが出力される
from bedrock_agentcore import BedrockAgentCoreApp

# NG: トレースが出力されない（ログ・メトリクスは出るがトレースだけ欠落）
from bedrock_agentcore.runtime import BedrockAgentCoreApp
```

SDK のトップレベル `__init__.py` での Observability 初期化フックに乗らないことが原因と推測される。

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

## Slack → Lambda → AgentCore の実装パターン

Slack Bot を API Gateway + Lambda 経由で AgentCore Runtime に繋ぐ構成で踏んだ罠。

### Slack の 3 秒 ACK 制約は Lambda 自己 invoke で回避

Slack Events API は **3 秒以内に 200 を返さないとリトライ**（最大3回）してくる。ACK を返す前に AgentCore を同期 invoke（数十秒かかる）すると、毎回タイムアウト→リトライになり、重複排除で握りつぶして延命する不安定な状態になる。

対策: 署名検証と重複排除（DynamoDB 条件付き Put 等）まで同期でやり、本処理は **Lambda が自分自身を `InvocationType: Event`（非同期）で invoke** して即 200 を返す。ハンドラ冒頭で `mode` を見て「非同期本処理」分岐に入れる。

- 自己 invoke には `lambda:InvokeFunction` 権限が要るが、`handler.functionArn`（GetAtt）を自分のロールポリシーに入れると **Function → DefaultPolicy → Function の循環依存**になる。関数名を固定すると今度は Lambda 置き換えを招き、他スタックが参照する ARN エクスポートをロックして deploy が詰まる。**`スタック名-論理ID*` へのワイルドカード ARN**（`formatArn` でリテラル生成）で許可するのが安全な落とし所。
- 注意: 自己 invoke 後の本処理失敗は Slack にリトライされない。エラー時のスレッド返信が唯一の通知手段になるので、重複排除は「受付側で先に」済ませる順序を保つ。

### Slack Web API は読み取り系が form-urlencoded 必須

`chat.postMessage` 等の書き込み系は JSON body で通るが、**`conversations.replies` / `conversations.history` / `conversations.info` / `files.getUploadURLExternal` などは JSON だと `invalid_arguments`** になる。`application/x-www-form-urlencoded` で送る。メソッドごとに Content-Type を出し分ける実装にし、urlencoded 必須メソッドは Set で一元管理すると次に増えても 1 行で済む。

- スレッド文脈取得（`conversations.replies`）を JSON で送っていて実は一度も成功していなかった、という潜在バグが「同一チャンネルのメンションだけ」の運用では表面化せず、DM / 複数チャンネル対応で初めて露見した事例あり。

### 非同期パイプラインの DynamoDB ゾンビレコード対策

「登録 → 数分後に別ジョブ（画像生成等）が `update_item` で結果を書き戻す」構成では、その間にレコードが削除されると **`update_item` の upsert 動作で部分レコードが復活**する（`title` 等の必須属性が無い不完全な項目が生まれる）。これが後段のバッチ（KB 同期で `record["title"]` 参照等）を `KeyError` で全滅させることがある。

対策:
- 更新系は `ConditionExpression="attribute_exists(pk)"` を標準装備にし、削除済みキーへの書き戻しを弾く。
- バッチ側は不完全レコードを 1 件で全体を止めずスキップ + 警告ログ。
- 非同期パイプラインがある設計では、`update_item` を素の upsert のまま使わないのを原則にする。
