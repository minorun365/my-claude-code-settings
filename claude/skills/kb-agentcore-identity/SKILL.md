---
name: kb-agentcore-identity
description: AgentCore Identity（アウトバウンド認証）のナレッジ。3LO/M2M/デコレータ分離/callback等
user-invocable: true
---

# AgentCore Identity（アウトバウンド認証）

Bedrock AgentCore Identity を使った外部サービスとの OAuth2 連携パターンを記録する。

## `@requires_access_token` と `@tool` は必ず分離する

`@tool` と `@requires_access_token` を同じ関数にスタックすると、パラメータ解析が干渉してツールが正しく動作しない（エージェントが `access_token` を入力パラメータとして要求してしまう）。

```python
# ❌ NG: デコレータをスタック → パラメータ干渉
@tool
@requires_access_token(provider_name="my-provider", scopes=[...], auth_flow="USER_FEDERATION")
async def get_pages(*, access_token: str):
    ...

# ✅ OK: トークン取得とツールを分離
@requires_access_token(provider_name="my-provider", scopes=[...], auth_flow="USER_FEDERATION",
    on_auth_url=lambda url: print(f"認可URL: {url}"),
    callback_url="http://localhost:9090/oauth2/callback")
def get_token(access_token: str = ""):
    return access_token

@tool
def get_pages():
    """外部APIのページ一覧を取得する"""
    token = get_token()
    response = httpx.get("https://api.example.com/pages",
        headers={"Authorization": f"Bearer {token}"})
    return response.json()
```

## USER_FEDERATION は同期関数でも動作する

`auth_flow="USER_FEDERATION"` でも `def`（同期関数）で定義可能。SDK 内部でポーリングをブロッキング実行する。`async def` + `asyncio.run_until_complete()` は BedrockAgentCoreApp の async コンテキストと競合するため避ける。

## 3LO (USER_FEDERATION) フローにはローカル callback サーバーが必要

3LO フローの callback は2段階で動作する：

1. Atlassian 等の IdP → **AgentCore callback**（`/identities/oauth2/callback/{providerId}?code=XXX&state=YYY`）→ code exchange
2. AgentCore → **アプリの callback サーバー**（`?session_id=...`）→ `CompleteResourceTokenAuth` を呼ぶ

`callback_url` に AgentCore の callback endpoint 自体を指定するとバリデーションエラーになる（GitHub Issue #801）。アプリ側で callback サーバーを立てる必要がある。

```python
# callback_server.py（FastAPI で localhost:9090 に立てる）
from fastapi import FastAPI
from bedrock_agentcore.services.identity import IdentityClient, UserIdIdentifier

app = FastAPI()
identity_client = IdentityClient(region="us-east-1")

@app.get("/oauth2/callback")
async def handle_callback(session_id: str):
    identity_client.complete_resource_token_auth(
        session_uri=session_id,
        user_identifier=UserIdIdentifier(user_id="<user_id>"),
    )
    return {"status": "success"}
```

```python
# エージェント側：callback_url を localhost に向ける
@requires_access_token(
    provider_name="my-provider",
    scopes=["read:confluence-content.all", "offline_access"],
    auth_flow="USER_FEDERATION",
    on_auth_url=lambda url: print(f"BROWSER: {url}"),
    callback_url="http://localhost:9090/oauth2/callback",
)
def get_token(access_token: str = ""):
    return access_token
```

**セットアップ手順:**
1. Workload Identity の `allowedResourceOauth2ReturnUrls` に `http://localhost:9090/oauth2/callback` を追加
2. callback サーバーを起動（`uv run python callback_server.py`）
3. エージェントを実行、auth URL をブラウザで開いて認可
4. callback サーバーが `CompleteResourceTokenAuth` を呼び、ポーリングでトークン取得

**参考**: 公式サンプル `awslabs/amazon-bedrock-agentcore-samples` の `05-Outbound_Auth_3lo/oauth2_callback_server.py`

## M2M (client_credentials) フローの互換性問題

AgentCore Identity の M2M フローは標準 `grant_type=client_credentials` を使用するが、多くの外部プロバイダーが独自仕様を持つため互換性に注意：

| プロバイダー | M2M結果 | 原因 |
|-------------|--------|------|
| Zoom | ❌ トークン取得成功、API拒否 | `grant_type=account_credentials` + `account_id` が必要 |
| GitHub | ❌ トークン取得失敗 | Token endpoint レスポンス形式が非標準 |
| Atlassian | △ サイトアクセス権なし | サービスアカウント設定が別途必要 |

**結論**: M2M は実務上イレギュラー。3LO (USER_FEDERATION) が主流パターン。

## BedrockAgentCoreApp の初期化タイムアウト

AgentCore Runtime は初期化を30秒以内に完了する必要がある。モジュールレベルで `agent(...)` を実行すると、3LO のポーリングで初期化がブロックされタイムアウトする。

```python
# ❌ NG: モジュールレベルで実行 → 30秒タイムアウト
agent = Agent(tools=[my_tool])
agent("処理を実行して")

# ✅ OK: BedrockAgentCoreApp + @app.entrypoint で invoke 時に実行
app = BedrockAgentCoreApp()

@app.entrypoint
def handle_request(request, context=None):
    agent = Agent(tools=[my_tool])
    result = agent(request.get("prompt", ""))
    return {"response": str(result)}

if __name__ == "__main__":
    app.run()
```
