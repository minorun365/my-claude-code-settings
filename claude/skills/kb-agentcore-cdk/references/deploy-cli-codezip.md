# Deploy, CLI, and CodeZip pitfalls

## 目次

- update_agent_runtime の注意点
  - update_agent_runtime は全フィールド置換（パッチ更新ではない）
  - agentcore deploy で認証設定がリセットされる
- JWT 認証時の SDK/CLI 制約
  - JWT認証時に SDK/CLI で Authorization method mismatch
- CodeZip デプロイの罠
  - `--build CodeZip` は Playwright driver の実行権限で失敗する
  - Runtime の artifact type は in-place 更新できない
  - CodeZip の手動再パッケージングで UPDATE_FAILED
- トラブルシューティング
  - AgentCore Runtime を CLI から手動呼び出しする方法
- AgentCore CLI (`@aws/agentcore`)
  - インストール
  - プロジェクト作成（対話式 vs 非対話式）
  - デプロイの非対話化（aws-targets.json 直書き方式）
  - `aws-targets.json` のスキーマ（v1）
  - agentcore.json の runtimes 定義
  - 他の便利コマンド
  - TUI を完全自動化したいとき（最後の手段）

## update_agent_runtime の注意点

### update_agent_runtime は全フィールド置換（パッチ更新ではない）

**症状**: `bedrock-agentcore-control` の `update_agent_runtime` API でコードを更新したら、環境変数と認証設定（authorizerConfiguration）が消えた

**原因**: `update_agent_runtime` は省略したフィールドを空でリセットする（パッチ更新ではなく全置換）

**解決策**: 更新時に全パラメータを明示的に渡す

```python
control.update_agent_runtime(
    agentRuntimeId='...',
    roleArn='...',                        # 必須
    networkConfiguration={...},           # 必須
    agentRuntimeArtifact={...},           # コード
    environmentVariables={                # 省略すると空になる！
        'AWS_DEFAULT_REGION': 'us-east-1',
        'MEMORY_ID': '...',
    },
    authorizerConfiguration={             # 省略すると認証なしになる！
        'customJWTAuthorizer': {
            'discoveryUrl': '...',
            'allowedClients': ['...'],
        }
    },
)
```

**補足**: `agentcore deploy` CLI はインタラクティブターミナル（Ink/raw mode）が必要で、CI/CD やサブプロセスからは実行できない。非対話環境では boto3 の `update_agent_runtime` を使う。

### agentcore deploy で認証設定がリセットされる

**症状**: `agentcore deploy` 実行後、マネコンで設定した `authorizerConfiguration`（Cognito JWT 等）が空になる

**原因**: AgentCore CLI の deploy は `authorizerConfiguration` を管理しない。デプロイ時にランタイム設定が上書きされ、認証設定が空になる

**解決策**: デプロイ後にマネコンまたは API で認証設定を再適用する。環境変数は `agentcore.json` の `envVars` で管理すれば保持される

---

## JWT 認証時の SDK/CLI 制約

### JWT認証時に SDK/CLI で Authorization method mismatch

**症状**: `agentcore invoke` や boto3 の `invoke_agent_runtime` で呼び出すと以下のエラー：
```
Authorization method mismatch. The agent is configured for a different authorization method than what was used in your request.
```

**原因**: Runtime に `customJWTAuthorizer` が設定されている場合、SigV4（IAM認証）での呼び出しは拒否される

**解決策**: HTTPS エンドポイントに直接リクエストし、`Authorization: Bearer {JWT}` ヘッダーで認証する

```bash
curl -X POST \
  "https://bedrock-agentcore.${REGION}.amazonaws.com/runtimes/${ENCODED_ARN}/invocations?qualifier=DEFAULT" \
  -H "Authorization: Bearer ${JWT_TOKEN}" \
  -H "Content-Type: application/json" \
  -H "X-Amzn-Bedrock-AgentCore-Runtime-Session-Id: ${SESSION_ID}" \
  -d '{"prompt": "hello"}'
```

**注意**: `runtimeSessionId` は33〜256文字の制約あり。短いとバリデーションエラー。

---

## CodeZip デプロイの罠

### `--build CodeZip` は Playwright driver の実行権限で失敗する

**症状**: `agentcore add agent --build CodeZip` で作成したランタイムで `AgentCoreBrowser` / `strands_tools.browser` を使うと、Browser ツール呼び出しで次のエラー：

```
Error: PermissionError - [Errno 13] Permission denied: '/var/task/playwright/driver/node'
```

**原因**: CodeZip（S3 ZIP デプロイ）は zip アーカイブ展開時にファイルの実行権限（+x）を保持しない。Playwright が同梱する `driver/node` バイナリの実行ビットが落ちたまま展開されるため、ブラウザ自動化の裏側で node プロセスを起動できない。

**対策**: Playwright を使うエージェントは `--build Container`（ECR デプロイ）を指定する。Dockerfile 内で `pip install playwright && playwright install` を実行すれば実行権限が正しく付与されたままデプロイされる。

```bash
# ✅ Playwright / Browser tool を使うなら Container
agentcore add agent --name <name> --build Container --framework Strands ...

# ❌ NG: CodeZip で playwright を含むと driver/node の実行権限問題で失敗
```

他にも Chromium、Node.js ドライバ、ネイティブ拡張など実行ビットが必要なバイナリを含むアプリでは同じ問題が起きる。

### Runtime の artifact type は in-place 更新できない

**症状**: 一度 CodeZip で作った AgentCore Runtime を CDK 経由で Container に切り替えようとすると、CloudFormation が次のエラーで UPDATE_ROLLBACK：

```
Invalid request provided: Agent artifact type cannot be updated
(Service: BedrockAgentCoreControl, Status Code: 400)
```

**原因**: `AWS::BedrockAgentCore::Runtime` リソースの `AgentRuntimeArtifact.CodeConfiguration` と `ContainerConfiguration` は相互排他で、作成後の切替不可。

**対策**: スタックごと作り直す。CloudFormation スタックを `aws cloudformation delete-stack` で削除してから `agentcore deploy` を再実行。Runtime ARN は変わるので：

- Amplify アプリ環境変数 `NEXT_PUBLIC_AGENT_ARN` を新ARNに更新して再ビルド
- Workload Identity 許可URLの再設定
- 実行ロールへの IAM ポリシー再アタッチ
- `update-agent-runtime` で環境変数・JWT authorizer を再適用

```bash
aws cloudformation delete-stack --stack-name <stack-name>
# DELETE_COMPLETE まで待機（通常数分）
agentcore deploy -y --verbose
```

教訓：**最初から正しい `--build` を選ぶ**。Playwright や Chromium を使うなら Container 一択。

### CodeZip の手動再パッケージングで UPDATE_FAILED

**症状**: `update_agent_runtime` で新しい ZIP をアップロードしてデプロイすると `UPDATE_FAILED` になる。CloudWatch にランタイムログが一切出力されない（コンテナが起動前に失敗）

**原因**: agentcore CLI が作成した ZIP と、ステージングディレクトリから `zip -r` で新規作成した ZIP では内部構造が異なる。AgentCore のデプロイパイプラインが ZIP 構造を厳密にチェックしている可能性がある

**解決策**: 前回成功した ZIP をコピーして `zip -u` で差分更新する

```bash
# ❌ NG: ステージングディレクトリから新規作成 → UPDATE_FAILED
cd staging/ && zip -r /tmp/new.zip .

# ✅ OK: 前回成功の ZIP をベースに差分更新
cp /tmp/v21_success.zip /tmp/v24.zip
# main.py を修正してから:
cd /tmp/extract/ && zip -u /tmp/v24.zip main.py
```

**補足**:
- `UPDATE_FAILED` でも `statusReason` フィールドがないため、API からエラー詳細を取得できない
- CloudWatch にログが出ない場合はコンテナ起動前の失敗（ZIP 構造の問題やモジュール初期化タイムアウト）を疑う
- `get-agent-runtime` の `liveVersion` で現在稼働中のバージョンを確認可能

---

## トラブルシューティング

### AgentCore Runtime を CLI から手動呼び出しする方法

**payload は base64 エンコードが必要**:

```bash
PAYLOAD=$(echo -n '{"prompt": "Check emails and notify Slack"}' | base64)
aws bedrock-agentcore invoke-agent-runtime \
  --agent-runtime-arn "arn:aws:bedrock-agentcore:REGION:ACCOUNT:runtime/RUNTIME_ID" \
  --payload "$PAYLOAD" \
  --content-type "application/json" \
  --profile <profile> \
  --region us-east-1 \
  /tmp/response.txt
```

**日本語の payload は使えない**:

```
string argument should contain only ASCII characters
```

AWS CLI がマルチバイト文字を受け付けない。システムプロンプトが日本語なら英語プロンプトでも問題なく動く。

**レスポンスはファイルに保存**:
最後の引数がレスポンスを書き出すファイルパス（省略不可）。

---

## AgentCore CLI (`@aws/agentcore`)

CDK の生コードではなく公式 CLI でエージェントプロジェクトを作る場合のノウハウ。v0.8.2 時点での検証結果。

### インストール

```bash
npm install -g @aws/agentcore
agentcore --version  # 0.8.2
```

バージョン固定しない方針（プレビュー版）。古いCLIは動かなくなるリスクがあるため常に最新を使う。

### プロジェクト作成（対話式 vs 非対話式）

**対話式（ブラウザ Codespace 等の TTY あり環境）**:
```bash
agentcore create   # TUI起動 → ガイド付きプロンプト
```

**非対話式（CI/CD / SSH 経由）**:
```bash
# ワンショットでフル生成（Python, Strands, Bedrock, memory なし）
agentcore create --name handson --defaults

# Agent 名をカスタマイズしたいとき
agentcore create --name handson --no-agent --skip-install
cd handson
agentcore add agent --name MyAgent --type create --language Python \
  --framework Strands --model-provider Bedrock --memory none \
  --build CodeZip --protocol HTTP
```

**罠**:
- `--skip-install` を付けると `agentcore/cdk/` の `npm install` がスキップされ、後で deploy 時に `tsc: not found` で失敗する。必要なら `cd agentcore/cdk && npm install` を手動実行
- `agentcore add agent` は `--language` が必須（無いと `--language is required` エラー）

### デプロイの非対話化（aws-targets.json 直書き方式）

`agentcore deploy -y` は TTY 無しでも走るが、**`agentcore/aws-targets.json` が空 `[]` のままだと `Target "default" not found in aws-targets.json` で即失敗**する。TUI での deploy 初回に自動で埋まるが、CI/CD では直書きが必要：

```bash
# AWS アカウントID を自動取得してファイルを作成
ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
printf '[{"name":"default","account":"%s","region":"us-east-1"}]' "$ACCOUNT" \
  > agentcore/aws-targets.json

# 非対話 deploy
agentcore deploy -y --json
```

### `aws-targets.json` のスキーマ（v1）

`aws/agentcore-cli` の公式 `docs/configuration.md` と `schemas/agentcore.schema.v1.json` で確認済：

```json
[
  {
    "name": "default",
    "account": "123456789012",
    "region": "us-east-1",
    "description": "optional"
  }
]
```

- ルートは **配列**（空 `[]` だとデプロイ失敗）
- `name` が `--target <name>` で指定する識別子。デフォルトは `"default"`
- `account` は12桁のAWSアカウントID（必須）
- `region` 必須
- `AGENTCORE_*` 環境変数で初期値を渡す仕組みは**ない**（v0.8.2時点）

### agentcore.json の runtimes 定義

`agentcore create --defaults` で生成される `agentcore/agentcore.json` の `runtimes` 要素：

```json
{
  "name": "MyAgent",
  "build": "CodeZip",
  "entrypoint": "main.py",
  "codeLocation": "app/MyAgent/",
  "runtimeVersion": "PYTHON_3_14",
  "networkMode": "PUBLIC",
  "protocol": "HTTP"
}
```

- `build`: `CodeZip`（S3直接デプロイ、Pythonのみ・最大250MB）または `Container`（ECR、任意言語・最大2GB）
- `protocol`: `HTTP` / `MCP` / `A2A` を選べる

### 他の便利コマンド

- `agentcore invoke "<prompt>" --stream` - CLI からデプロイ済みエージェントを呼び出し
- `agentcore logs --follow` - CloudWatch Logs のストリーミング
- `agentcore status` - 全リソースの状態
- `agentcore dev` - ローカル dev サーバー起動（`/invocations` を localhost で）
- `agentcore package` - デプロイ用アーティファクトのビルドのみ

### TUI を完全自動化したいとき（最後の手段）

1. `script -qec 'agentcore deploy' /dev/null` で PTY 疑似確保
2. `sudo apt-get install -y expect` → expect スクリプトで画面遷移
3. `gh codespace ssh --codespace <name> -- -tt "<command>"` で OpenSSH の PTY 強制割当
4. 公式 TUI Harness（`aws/agentcore-cli` の `src/mcp-harness/`、`npm run build:harness` 要）で MCP 経由の `tui_launch` / `tui_send_keys` / `tui_wait_for`

ただし、書籍ハンズオンの代理検証など検証目的なら「**`aws-targets.json` 直書き＋`deploy -y --json`**」で完結する（最も安定）。

---
