# Bedrock AgentCore との統合

## Bedrock AgentCore との統合

### 基本構造
```python
from bedrock_agentcore import BedrockAgentCoreApp
from strands import Agent

# モデルIDは世代交代が速い。実在は `aws bedrock list-inference-profiles` で確認する
MODEL_ID = "<推論プロファイルID>"

app = BedrockAgentCoreApp()
agent = Agent(model=MODEL_ID)

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

### 複数ユーザーのセッション管理

クライアントが送った `session_id` だけをキーに会話履歴やAgentインスタンスを共有しない。

- 認証済み利用者とセッションIDの対応をバックエンドで管理する
- セッションIDはサーバー側で発行し、利用時に所有者を検証する
- 会話状態はTTL付きの永続ストアへ保存し、プロセスのグローバル変数へ置かない
- ログにはセッションIDの全文、プロンプト、認証情報を出さない

### SSE keep-alive パターン（長時間処理のコネクション維持）

同期的な重い処理（ファイル変換、外部API呼び出し等）をSSEで返す場合、処理中にkeep-aliveイベントを送信してコネクションを維持する。`asyncio.run_in_executor` + `asyncio.shield` + タイムアウトの組み合わせ。

```python
import asyncio
import logging

logger = logging.getLogger(__name__)

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
        except Exception:
            logger.exception("PPTX export failed")
            yield {"type": "error", "message": "ファイルの生成に失敗しました。"}
        return
```

**ポイント**:
- `asyncio.shield(task)` で TimeoutError 時もタスクがキャンセルされない
- `task.done()` でループ脱出を判定、`task.result()` で結果取得
- フロントエンドのSSEパーサーは未知の `type` を無視するため、既存コードの変更不要

LLMが生成したMarkdownをHTMLとして表示する場合は、許可する要素と属性を限定してサニタイズする。

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

**Bedrockキャッシュの課金構造**（単価は改定されるので、比率だけ覚えて実額は公式の料金ページで確認する）:

| 種別 | 通常インプットとの比 | 備考 |
|------|------|------|
| 通常インプット | 1.0 倍 | キャッシュなし時 |
| キャッシュライト | 約 1.25 倍 | 初回だけ割高になる |
| キャッシュリード | 約 0.1 倍 | 2回目以降（**約90%オフ**） |

初回に25%上乗せして2回目以降が9割引なので、**同じプレフィックスを2回以上使うなら必ず得になる**。

---
