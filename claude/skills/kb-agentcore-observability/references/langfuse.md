# Langfuse 連携

## Langfuse連携（サードパーティOTEL送信）

OTELベースなので、CloudWatch以外のバックエンドにもトレースを送信可能。Langfuseとの連携例:

```python
import base64
import os

from dotenv import load_dotenv
from strands import Agent
from strands.telemetry import StrandsTelemetry

load_dotenv()

LANGFUSE_PUBLIC_KEY = os.environ["LANGFUSE_PUBLIC_KEY"]
LANGFUSE_SECRET_KEY = os.environ["LANGFUSE_SECRET_KEY"]
LANGFUSE_HOST = os.environ.get("LANGFUSE_HOST", "https://cloud.langfuse.com")

# OTLPエクスポーターの認証ヘッダーを生成（HTTP Basic認証）
auth = base64.b64encode(
    f"{LANGFUSE_PUBLIC_KEY}:{LANGFUSE_SECRET_KEY}".encode()
).decode()

# Langfuseにトレースを送信
StrandsTelemetry().setup_otlp_exporter(
    endpoint=f"{LANGFUSE_HOST}/api/public/otel/v1/traces",
    headers={"Authorization": f"Basic {auth}"},
)

agent = Agent()
response = agent("こんにちは")
```

**ポイント**:
- Langfuse Cloud の Hobby プラン（無料）で動作確認済み
- トレース名 `invoke_agent Strands Agents` として記録される
- トークンコストの自動計算まで動作する
- AgentCore Runtime にデプロイする場合は `DISABLE_ADOT_OBSERVABILITY=True` 環境変数で ADOT を無効化する必要あり（競合防止）

---

