# AWS関連のナレッジ

プロジェクト横断で得たAWSの学びを記録する。

## Bedrock

- クロスリージョン推論のプレフィックスはリージョンで異なる: `us.`（バージニア/オレゴン）、`jp.`（東京）
- Bedrock AgentCoreは15リージョンで利用可能（us-east-1, us-west-2, ap-northeast-1 等）

## Lambda

- （学びを追記）

## IAM

### Bedrockモデル呼び出し権限

クロスリージョン推論（`us.anthropic.claude-*`形式）を使用する場合、以下の両方のリソースへの権限が必要：

```
arn:aws:bedrock:*::foundation-model/*       # 基盤モデル
arn:aws:bedrock:*:*:inference-profile/*     # 推論プロファイル
```

`foundation-model/*` だけでは `AccessDeniedException` が発生する。

## Cognito

### IDトークン vs アクセストークン

| トークン | 用途 | クライアントIDの格納先 |
|---------|------|---------------------|
| IDトークン | ユーザー情報（名前、メールなど）取得 | `aud` クレーム |
| アクセストークン | APIへのアクセス認可 | `client_id` クレーム |

API認証で `client_id` を検証する場合は**アクセストークン**を使用する。

## セキュリティ

### 機密情報の取り扱い

以下の情報はコードやドキュメントにベタ書きしない（GitHubに流出するリスクがあるため）：

| 情報 | 代替手段 |
|------|---------|
| AWSアカウントID | 環境変数、`amplify_outputs.json`から参照 |
| Cognito User Pool ID | `amplify_outputs.json`から参照 |
| Cognito Client ID | `amplify_outputs.json`から参照 |
| Identity Pool ID | `amplify_outputs.json`から参照 |
| APIキー（Tavily等） | 環境変数、Secrets Manager |
| ARN（実際のもの） | 形式の説明のみ記載（例: `arn:aws:..:{accountId}:...`） |

**例示用のダミー値**（これらはOK）:
- `123456789012`（12桁のダミーアカウントID）
- `arn:aws:service:region:123456789012:resource`

## その他

- （学びを追記）
