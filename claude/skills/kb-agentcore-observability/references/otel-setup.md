# OpenTelemetry セットアップとログ形式

## Observability（トレース）セットアップ

AgentCore Observability でトレースを出力する場合、以下の4点が**すべて**必要：

### 1. requirements.txt
```
strands-agents[otel]
aws-opentelemetry-distro
```

### 2. Dockerfile（`opentelemetry-instrument` で起動）
```dockerfile
CMD ["opentelemetry-instrument", "python", "agent.py"]
```

### 3. CDK環境変数
```typescript
environmentVariables: {
  AGENT_OBSERVABILITY_ENABLED: 'true',
  OTEL_PYTHON_DISTRO: 'aws_distro',
  OTEL_PYTHON_CONFIGURATOR: 'aws_configurator',
  OTEL_EXPORTER_OTLP_PROTOCOL: 'http/protobuf',
}
```

### 4. import パス（トップレベルから import すること）
```python
# OK: トレースが出力される
from bedrock_agentcore import BedrockAgentCoreApp

# NG: トレースが出力されない（ログ・メトリクスは出るがトレースだけ欠落）
from bedrock_agentcore.runtime import BedrockAgentCoreApp
```

**注意**: 上記4つすべてが必要。1つでも欠けるとトレースが出力されない。

### 5. CloudWatch Transaction Search（アカウントごとに1回）

```bash
aws xray get-trace-segment-destination --region us-east-1
# Destination: CloudWatchLogs, Status: ACTIVE であること
```

### 6. ログポリシー（アカウントごとに1回）

```bash
aws logs describe-resource-policies --region us-east-1
# TransactionSearchXRayAccess ポリシーが存在すること
```

### import パスの罠: runtime サブモジュール経由だとトレースが出ない

`from bedrock_agentcore.runtime import BedrockAgentCoreApp` を使うと、内部的には同じクラスが動くにもかかわらず、GenAI Observability の Traces View にトレースが一切表示されない。OTel のログ・メトリクスは正常に出力されるため、影響を受けるのはトレース（X-Ray スパン）のエクスポートのみ。SDK のトップレベル `__init__.py` での Observability 初期化フックに乗らないことが原因と推測される。

---

## OTELログ形式

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

---

