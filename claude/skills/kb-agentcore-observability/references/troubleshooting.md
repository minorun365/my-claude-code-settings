# トラブルシューティング・関連スキル・参考リンク

## トラブルシューティング

### ローカルから CloudWatch X-Ray へトレースが送信できない

**症状**: ADOT 自動計装（`opentelemetry-instrument`）でローカルから X-Ray OTLP エンドポイントにトレースを POST すると 200 OK が返るが、`aws/spans` ロググループや `get-trace-summaries` にトレースが現れない

**環境**:
- `OTLPAwsSpanExporter`（SigV4署名付き）で `https://xray.us-east-1.amazonaws.com/v1/traces` に送信
- Transaction Search は有効化済み（`ACTIVE` / `CloudWatchLogs`）
- X-Ray → CloudWatch Logs のリソースポリシーも設定済み

**原因**: Runtime 環境でのみ自動設定されるリソース属性（`cloud.platform: aws_bedrock_agentcore`、`cloud.resource_id`、`deployment.environment.name` 等）がないと、X-Ray / Transaction Search がトレースを GenAI Observability に記録しない可能性が高い

**対処法**: ローカル開発ではコンソールエクスポーターを使う（CloudWatch への送信は Runtime デプロイ時に自動で行われる）

```python
from strands.telemetry import StrandsTelemetry
StrandsTelemetry().setup_console_exporter()
```

**補足**: メトリクス（EMF形式）は `OTEL_EXPORTER_OTLP_LOGS_HEADERS` を設定すればローカルからでも CloudWatch Logs に正常に送信される。影響を受けるのはトレース（X-Ray スパン）のエクスポートのみ。

### OTEL ログ形式で invocation がカウントできない

**症状**: `filter @message like /invocations/` でログをカウントしているが、件数が0になる

**原因**: OTEL有効時、ログ形式がJSON（OTEL形式）に変わり、従来のパターンマッチが効かない

**解決策**: `session.id` をparseしてユニークカウントする

```
# 旧方式（OTELログでは効かない）
filter @message like /invocations/ or @message like /POST/

# 新方式（OTEL対応）
parse @message /"session\.id":\s*"(?<sid>[^"]+)"/
| filter ispresent(sid)
| stats count_distinct(sid) as sessions
```

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

## 関連スキル

- `/kb-strands-agentcore` - Strands Agents フレームワーク（Agent作成、ツール定義、イベント処理）
- `/kb-agentcore-cdk` - AgentCore CDK、デプロイ、ランタイム統合、コンテナ構成
- `/kb-agentcore-identity` - アウトバウンド認証（3LO/M2M/デコレータ分離/callback等）

## 参考リンク

- [Strands Agents 公式ドキュメント](https://strandsagents.com/)
- [GitHub リポジトリ](https://github.com/strands-agents/strands-agents)
- [Bedrock AgentCore 統合ガイド](https://docs.aws.amazon.com/bedrock/latest/userguide/agents-agentcore.html)
