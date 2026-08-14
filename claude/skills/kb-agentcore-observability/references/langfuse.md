# Langfuse 連携

## Langfuse連携（サードパーティOTEL送信）

OTELベースなので、CloudWatch以外のバックエンドにもトレースを送信可能。Langfuseとの連携例:

Langfuse CloudはAWSアカウント外のサービスである。プロンプト、LLM応答、ツール結果を送信する前に、対象データの外部送信可否、保存リージョン、保持期間、アクセス権を確認する。個人情報や秘密値は送信前にマスキングし、認証ヘッダー自体をログへ出さない。

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
- トレース名 `invoke_agent Strands Agents` として記録される
- トークンコストの自動計算まで動作する
- AgentCore Runtime にデプロイする場合は `DISABLE_ADOT_OBSERVABILITY=True` 環境変数で ADOT を無効化する必要あり（競合防止）

---
