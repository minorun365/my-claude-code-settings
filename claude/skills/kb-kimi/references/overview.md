# Kimi K2 ナレッジ overview・基本情報

# Kimi K2 ナレッジ

Moonshot AI の Kimi K2 Thinking モデル特有の問題とワークアラウンドを記録する。Claudeモデルとは挙動が異なる点が多いため、別スキルとして管理。

## 基本情報

### モデルID
```python
model = "moonshot.kimi-k2-thinking"
```

### Claudeとの差異

| 項目 | Claude | Kimi K2 Thinking |
|------|--------|------------------|
| クロスリージョン推論 | ✅ `us.`/`jp.` | ❌ なし |
| cache_prompt | ✅ 対応 | ❌ 非対応 |
| cache_tools | ✅ 対応 | ❌ 非対応 |
| ツール呼び出しの安定性 | ✅ 高い | ⚠️ 不安定（リトライ必要） |
| 思考プロセス（reasoning） | - | ✅ あり |

### BedrockModel設定の注意

Kimi K2使用時は`cache_prompt`と`cache_tools`を指定しないこと。指定するとAccessDeniedExceptionが発生する。

```python
from strands.models import BedrockModel

# ❌ NG: Kimi K2でキャッシュオプションを使用
model = BedrockModel(
    model_id="moonshot.kimi-k2-thinking",
    cache_prompt="default",  # AccessDeniedException
    cache_tools=True,        # AccessDeniedException
)

# ✅ OK: キャッシュオプションなし
model = BedrockModel(
    model_id="moonshot.kimi-k2-thinking",
)
```

---

