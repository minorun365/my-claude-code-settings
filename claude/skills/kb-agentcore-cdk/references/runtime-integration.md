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

---

## AgentCore Runtime のコスト（メモリ従量課金）の罠

AgentCore Runtime の請求で `USE1-Runtime:Consumption-based:Memory` が突出したら、まずこの罠を疑う。**モデル呼び出し料ではなく「セッションがアイドルで居座る空課金」が主因**なことが多い（実測では、月額の8割超がメモリ従量で、モデル料は1割未満という内訳になった）。

### 課金の仕組み（一次情報・2026-07 時点）

- **メモリ課金は「セッションが生存している間ずっと」発生し、アイドル中も止まらない**。CPU は I/O 待ちで消費ゼロなら課金ゼロだが、メモリは「その秒までのピークメモリ × 生存秒数」で毎秒課金され続ける。単価 **$0.00945/GB-Hour**、CPU $0.0895/vCPU-Hour（us-east-1）。128MB・1秒が下限。
- セッション状態は **Active → Idle → Terminated**。処理を返しても **デフォルトで 15分（`idleRuntimeSessionTimeout`=900秒）アイドルのまま provisioned で生存**し、その間もメモリを課金され続ける。最大 `maxLifetime` は 8時間。
- 非同期・バックグラウンド処理がヘルスチェックに `HealthyBusy` を返す間は Active 扱いで生き続ける → 意図せず長時間メモリを掴む。
- Runtime を「デプロイしているだけ（セッション0件）」ではコンピュート課金なし。課金はセッション単位。
- 逆算例: メモリ従量が月 $76 なら $76 ÷ $0.00945 ≒ 8,000 GB-Hours = 平均11GBを30日間確保し続けたのと同等。

### やりがちな構造（犯人）

- **高頻度ポーリング Scheduler × 15分アイドル**：`rate(2 minutes)` 等でバッチ mode を叩くと、1回の処理が数秒で終わっても新規セッションが15分居座る → セッションが重なって常時7〜8個生存 → 空ポーリングだけで固定費が積む。試験運用で人間トラフィックがゼロでもコストが出る。
- 定期実行系が呼び出しごとに新規 UUID セッションを作り、**`StopRuntimeSession` をどこも呼ばない**。

### lifecycle パラメータの範囲と適用単位（設計の分岐点）

`LifecycleConfiguration`（`CreateAgentRuntime`/`UpdateAgentRuntime` の入力）:

| パラメータ | 有効範囲 | デフォルト |
|---|---|---|
| `idleRuntimeSessionTimeout` | **60〜28800秒**（1秒単位） | 900（15分） |
| `maxLifetime` | 60〜28800秒 | 28800（8時間・上限固定、超過不可） |

- **idle は最短60秒**。0秒や数秒には設定不可（「極限まで短く」の底が60秒）。
- **lifecycle は Runtime 単位で固定**。`InvokeAgentRuntime`（データプレーン）の入力に lifecycle 系パラメータは無く、**呼び出し（セッション）ごとの出し分けは不可**。1つのRuntimeで「対話呼び出しはidle長め・バッチ呼び出しはidle極短」はできない。
- **セッション種別ごとに終わらせ方を変えたいときの2択**：①用途別に Runtime を分けてデプロイ（バッチ用 Runtime だけ idle=60秒）②`StopRuntimeSession` でアプリ側から早期終了（下記）。**Runtime分割はデプロイ面が増えるので、非対話バッチは②が第一候補**。

### `StopRuntimeSession` の呼び出し作法

- **呼ぶのはストリーム（SSE応答）を完全に読み切ってから**。早すぎると「stops any ongoing streaming responses」で自分の応答が途中で切れる。
- **呼び出し主体は呼び出し側（クライアント/Lambda）が定石**。`invoke_agent_runtime` した側が `runtimeSessionId` を追跡し、応答受信完了後に `stop_runtime_session(agentRuntimeArn=..., runtimeSessionId=..., qualifier='DEFAULT')` を finally 節で呼ぶ。
- 既終了セッションの二重 stop は `ResourceNotFoundException`(404) なので握りつぶしてよい。IAM は `bedrock-agentcore:StopRuntimeSession`。

### CDK での lifecycle 指定（L2・stable）

```python
from aws_cdk import Duration, aws_bedrockagentcore as agentcore
agentcore.Runtime(self, "runtime",
    runtime_name="...",
    agent_runtime_artifact=artifact,
    lifecycle_configuration=agentcore.LifecycleConfiguration(
        idle_runtime_session_timeout=Duration.minutes(1),  # 最小60秒
        max_lifetime=Duration.hours(4),
    ),
)
```

- L1 (`CfnRuntime.LifecycleConfigurationProperty`) は `IdleRuntimeSessionTimeout` / `MaxLifetime`（秒数）。
- ⚠️ 旧 alpha モジュール `aws_cdk.aws_bedrock_agentcore_alpha` の `LifecycleConfiguration` は **Deprecated**。安定版 `aws_cdk.aws_bedrockagentcore` を使う。

### 削減の主戦場（効果の大きい順）

1. **単発/バッチ処理は応答を返したら即 `StopRuntimeSession` を呼ぶ**（会話継続が不要なら最優先）。アイドル15分の空課金を丸ごと消せる。idle短縮と違い実質0秒で畳めるので、これが「セッション種別ごとに極短」の正攻法。
2. **`idleRuntimeSessionTimeout` を60秒へ短縮**（Runtime単位・安全網）。1のフォールバック＋対話系follow-upの尾を刈る。
3. **ポーリング頻度を下げる or イベント駆動化**。「2分毎に空ポーリング」を「書き込みイベントで起こす」に変えるのが一番効く。既にデバウンス（例: 締切epoch方式）があるなら、**SQS `DelaySeconds`（最大900秒）で遅延enqueue**すると既存の冪等ロジックをそのまま流用でき、DynamoDB Streams（即時発火で遅延を表現できない）より配線が近道。
4. **`maxLifetime` を絞る**（暴走生存の上限）／`HealthyBusy` を返し続けていないか点検／ピークメモリ（常駐ライブラリ・インメモリキャッシュ）を削る。
5. 状態は「セッションを生かして保持」せず DynamoDB 等の外部に逃がし、セッションは短命にするのが公式の設計指針。

### 「削除」か「idle短縮」かの判断（コスト最適化の勘所）

- **Runtime は「存在するだけ」では課金されない。セッション起動時のみ consumption 課金**（メモリ GB-Hours / vCPU）。ECR/コードのストレージ課金は別途少額。
- よって **呼ばれていない放置 Runtime の compute は実質 $0**。棚卸しで消す価値はある（誤呼び出し防止・ECR・混乱回避）が、コスト削減の主効果ではない。
- **メモリ課金を積んでいるのは"現に呼ばれている" Runtime**（トークン課金の有無が実利用の判定材料になる）。ここは削除ではなく **idle短縮＋StopRuntimeSession** で尾引きを削るのが効く。
- 原則：**使わないデモ／重複（個人名・検証フェーズ名を付けた枝など）は削除、現役本体は短縮**。UsageType内訳で「Memoryが支配的かつトークン課金ゼロ＝純アイドル」なら削除が最も効き、「トークン課金あり＝実利用＋尾引き」なら短縮が本命。

### コスト調査の手順（月額タグに慌てず「継続 vs 一過性」を切り分ける）

「Projectタグの月額が高い」だけで対策に走らない。**存在課金でない以上、高い月額が"既に止まった一過性のバースト"のことがある**（たとえば月の前半に手動デモが集中しただけで、後半はゼロ・現在の run-rate は保管料のみ、という形）。切り分け手順：

1. **Cost Explorer を DAILY で**取る（`get-cost-and-usage` Granularity=DAILY）。平坦に毎日課金＝継続、山型で最近ゼロ＝一過性。
2. **CloudWatch `AWS/Bedrock-AgentCore` の `Invocations`/`SessionCount`** をRuntime ARN別に取る。ゼロなら呼ばれていない＝compute課金なし。`list-metrics` で実際のメトリクス名・ディメンションを先に確認（SEARCH式で全ディメンション網羅すると取りこぼしを防げる）。
3. **EventBridge Scheduler / Rule** を確認（`scheduler list-schedules`、`events list-rules`）。意図しない定期呼び出し元があれば、idle短縮より先にそれを止めるのが本命。
4. 一過性と分かったら**対応不要**。残る保管料（Secrets Manager・ECR）だけ気になれば棚卸し削除。

### 一次情報（2026-07-23 取得）

- 料金（課金対象の原文・単価）: https://aws.amazon.com/bedrock/agentcore/pricing/
- ライフサイクル Quota（idle 15分 / max 8時間）: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/bedrock-agentcore-limits.html
- StopRuntimeSession: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-stop-session.html
- 請求可視化メトリクス `MemoryUsed-GBHours` / `CPUUsed-vCPUHours`: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/observability-runtime-metrics.html
