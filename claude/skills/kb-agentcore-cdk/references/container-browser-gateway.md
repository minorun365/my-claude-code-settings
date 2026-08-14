# Containers, browser tool, and gateway

## 目次

- Dockerfileの例
- コンテナライフサイクルと環境変数
  - コンテナはセッション単位でキャッシュされる
  - CDK デプロイしてもコンテナはすぐに入れ替わらない
  - 定期実行×固定セッションIDは「デプロイが永遠に反映されない」罠
- ツール単位のアクセス制御パターン
  - 実装パターン
- AgentCoreBrowser（ビルトインブラウザツール）
  - ツール登録の注意: `.browser` メソッドを渡す
  - AgentCoreBrowser はリモートブラウザ（Playwright ローカルドライバー不要）
  - `strands_tools.browser.AgentCoreBrowser` も Playwright driver を必要とする
  - CodeZip デプロイ時の Playwright 実行権限問題（LocalChromiumBrowser のみ）
  - Browser Tool の IAM 権限
- AgentCore Gateway Policy
  - ENFORCE モードが AWS_IAM で Internal Failure
- WebSocket 認証
  - AgentCore WebSocket: JWT 認証が使えない
- Dockerfile: PyAudio ビルド失敗（strands-agents[bidi]）

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

### 定期実行×固定セッションIDは「デプロイが永遠に反映されない」罠

EventBridge Scheduler などの定期実行で **毎回同じ `runtimeSessionId`** を使うと、実行間隔がアイドルタイムアウト（15分）より短い場合、セッションが延命され続けて**旧バージョンのコンテナが永遠に生き残る**。`cdk deploy` は成功し、エンドポイントの `liveVersion` も新しくなるのに、定期実行だけ旧コードで動き続ける。


**対処法（推奨順）**:

1. **定期実行・バッチ系は毎回ランダムなセッションIDにする**（会話状態が不要なら固定にする意味がない）

```typescript
function buildAgentRuntimeSessionId(request: CaseAgentRequest): string {
  // 定期実行系はセッション固定するとデプロイが反映されないため毎回新セッション
  if (request.mode !== "slack_app_mention") {
    return `my-bot-${randomUUID()}`;
  }
  // 対話系のみスレッド単位で安定化
  const hash = createHash("sha256").update(stableKey).digest("hex");
  return `my-bot-${hash}`;
}
```

2. デプロイ直後に `stop-runtime-session` で該当セッションを止める（セッションIDの逆算が必要で運用が面倒）

**確認方法**: 生成物のメタデータ（モデル名・プロンプトバージョン等）を DynamoDB 等に記録しておくと、「デプロイしたのに旧挙動」に気づける。エンドポイントは `aws bedrock-agentcore-control get-agent-runtime-endpoint --endpoint-name DEFAULT` で `liveVersion` を確認できるが、**liveVersion が新しくても既存セッションは旧コンテナのまま**なので騙されないこと。

---

## ツール単位のアクセス制御

特定のツールを一部の利用者だけに許可する場合は、エージェントへ渡された任意の `user_id` を信用しない。

- JWT の署名・issuer・audience・有効期限を検証し、認証済み claim から利用者を特定する
- 可能なら AgentCore Gateway の Policy Engine など、エージェントコード外の認可層で制御する
- 設定が欠けた場合は許可せず、**デフォルト拒否**にする
- 利用者情報をモジュールのグローバル変数へ保存しない。認証コンテキストからリクエスト単位で渡す
- セッションIDと認証済み利用者の対応をバックエンドで管理し、クライアントによる別利用者のID指定を拒否する

開発時に固定IDを使う場合も、公開サンプルへ実在のIDや許可リストを含めない。

---

## AgentCoreBrowser（ビルトインブラウザツール）

### ツール登録の注意: `.browser` メソッドを渡す

`AgentCoreBrowser()` インスタンスをそのまま `tools` に渡すと「unrecognized tool specification」エラーになる。`@tool` デコレータ付きの `.browser` メソッドを渡す必要がある。

```python
from strands_tools.browser import AgentCoreBrowser

browser = AgentCoreBrowser()

# NG: インスタンスそのまま -> unrecognized tool specification
agent = Agent(tools=[browser, ...])

# OK: .browser メソッドを渡す
agent = Agent(tools=[browser.browser, ...])
```

`LocalChromiumBrowser` も同様のパターン（`local.browser`）。

### AgentCoreBrowser はリモートブラウザ（Playwright ローカルドライバー不要）

`AgentCoreBrowser()` は AgentCore Browser Service（リモート）を呼び出すため、ローカルの Playwright ドライバー（node バイナリ）は不要。`shutil.copy2` で 118MB の node バイナリをコピーするワークアラウンドを入れると、モジュール初期化でタイムアウトしてデプロイが失敗する。

```python
# NG: AgentCoreBrowser にはこのワークアラウンドは不要（デプロイ失敗の原因）
import shutil, stat
_node_src = "/var/task/playwright/driver/node"
shutil.copy2(_node_src, "/tmp/playwright_node")  # 118MBコピー -> タイムアウト

# OK: AgentCoreBrowser はそのまま使える
from strands_tools.browser import AgentCoreBrowser
browser = AgentCoreBrowser()
agent = Agent(tools=[browser.browser, ...])
```

### `strands_tools.browser.AgentCoreBrowser` も Playwright driver を必要とする

解説記事や書籍で「AgentCoreBrowser はリモートブラウザなので Playwright のローカルドライバー不要」と説明されることがあるが、実際には `strands_tools.browser.AgentCoreBrowser` は内部で Playwright の CDP クライアントを使って AgentCore 側のリモートブラウザに WebSocket 接続する。この **CDP 接続に `playwright/driver/node` バイナリの起動が必要** なので、CodeZip デプロイで実行権限が落ちると `PermissionError: /var/task/playwright/driver/node` で失敗する。

→ **AgentCoreBrowser を使うエージェントも Container デプロイ必須**。「リモートブラウザだから軽量」と説明されていても、ローカルランタイム側に Playwright driver は依然として必要。

### CodeZip デプロイ時の Playwright 実行権限問題（LocalChromiumBrowser のみ）

**`LocalChromiumBrowser` を使う場合のみ**、CodeZip パッケージングで Playwright ドライバーの実行ビット（`+x`）が失われる。`AgentCoreBrowser`（リモートブラウザ）ではこの問題は発生しない。

**解決策**: `/tmp` にコピーして `PLAYWRIGHT_NODEJS_PATH` 環境変数で指定（`get_agent()` 内の遅延初期化で実行すること）

**ポイント**:
- `/var/task/` は読み取り専用のため `os.chmod()` は効かない
- Playwright 1.58.0 の `_driver.py` で `PLAYWRIGHT_NODEJS_PATH` 環境変数がサポートされている
- Docker デプロイの場合はこの問題は発生しない（Dockerfile で権限設定可能）
- **モジュールレベルで 118MB のファイルコピーを実行するとデプロイ時のヘルスチェックでタイムアウトする**

### Browser Tool の IAM 権限

`agentcore deploy` が作成する開発用ロールだけでは、Browser Tool の呼び出し権限が不足する場合がある。

AccessDenied に表示されたアクションを最新の公式IAMリファレンスで確認し、対象BrowserリソースのARNへ限定して追加する。原因切り分け目的でも、サービス全体・全リソースを許可するポリシーを恒久設定に使わない。CLIが生成する広いポリシーは開発・検証用として扱い、本番ロールは必要なアクションとリソースから作り直す。

---

## AgentCore Gateway Policy

### ENFORCE モードが AWS_IAM で Internal Failure

**症状**: `authorizerType: AWS_IAM` のゲートウェイに Policy Engine を ENFORCE モードで関連付けると、`tools/list` / `tools/call` が以下のエラーで失敗する：
```
Tool Execution Denied: Policy Evaluation Internal Failure
```
LOG_ONLY モードでは正常にツール呼び出しが通過する。

**原因**: **Policy Engine の ENFORCE は `CUSTOM_JWT`（OAuth/Cognito）認証専用**。Cedar スキーマの Principal Type が `AgentCore::OAuthUser` 固定であり、JWT の `sub` クレームから principal を構築する設計。`AWS_IAM` 認証では principal エンティティを構築できず Internal Failure になる。

**解決策**: Policy Engine（特に ENFORCE モード）を使うには `CUSTOM_JWT` 認証のゲートウェイが必要

```python
# NG: AWS_IAM + ENFORCE → Internal Failure
agentcore.create_gateway(
    name="my-gateway",
    authorizerType="AWS_IAM",
    policyEngineConfiguration={"enforcementMode": "ENFORCE", ...},
)

# OK: CUSTOM_JWT + ENFORCE → 動作する
agentcore.create_gateway(
    name="my-gateway",
    authorizerType="CUSTOM_JWT",
    authorizerConfiguration={"usingJWT": {"discoveryUrl": "https://cognito-idp.../.well-known/openid-configuration", ...}},
    policyEngineConfiguration={"enforcementMode": "ENFORCE", ...},
)
```

**補足**:
- `authorizerType` は既存ゲートウェイでは変更不可（`update_gateway` で `ValidationException`）。新規作成が必要
- Cedar ポリシーで `principal.hasTag("department")` 等を使う場合、JWT トークンにカスタムクレームが必要

---

## WebSocket 認証

### AgentCore WebSocket: JWT 認証が使えない

**症状**: ブラウザから AgentCore の WebSocket エンドポイントに接続できない（認証エラー）

**原因**: `RuntimeAuthorizerConfiguration.usingJWT()` で設定した JWT 認証は HTTP invocations 用。ブラウザの WebSocket API はカスタムヘッダーを設定できないため、JWT トークンを渡せない

**解決策**: JWT 認証を削除し、IAM (SigV4) 事前署名 URL + Cognito Identity Pool に変更

```typescript
// CDK: Identity Pool の認証済みロールに権限付与
authenticatedRole.addToPrincipalPolicy(new iam.PolicyStatement({
  actions: ['bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStream'],
  resources: [runtime.agentRuntimeArn, `${runtime.agentRuntimeArn}/*`],
}));
```

```typescript
// ブラウザ: SigV4 presigned URL で WebSocket 接続
const signer = new SignatureV4({
  service: 'bedrock-agentcore', region, credentials, sha256: Sha256,
});
const presigned = await signer.presign(request, { expiresIn: 300 });
const ws = new WebSocket(`wss://...?${queryString}`);
```

---

## Dockerfile: PyAudio ビルド失敗（strands-agents[bidi]）

**症状**: Docker ビルド時に `strands-agents[bidi]` のインストールで PyAudio のビルドが失敗する

**原因**: Python slim イメージには C コンパイラと PortAudio ライブラリがない

**解決策**: `portaudio19-dev` + `build-essential` を追加

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    portaudio19-dev build-essential \
    && rm -rf /var/lib/apt/lists/*
```

---
