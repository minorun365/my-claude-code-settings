# 設計パターン・参考リンク

## 設計パターン

### モデル切り替え対応

ClaudeとKimi K2を動的に切り替えるアプリケーションでは、モデル固有の処理を分岐させる。

```python
def _get_model_config(model_type: str = "claude") -> dict:
    if model_type == "kimi":
        return {
            "model_id": "moonshot.kimi-k2-thinking",
            "cache_prompt": None,  # キャッシュ非対応
            "cache_tools": None,   # キャッシュ非対応
        }
    else:
        return {
            "model_id": f"us.anthropic.claude-sonnet-4-5-20250929-v1:0",
            "cache_prompt": "default",
            "cache_tools": True,
        }
```

### リトライはKimiのみ

```python
# リトライはKimi K2のみ（Claudeでは不要）
if tool_name_corrupted and model_type == "kimi":
    retry_count += 1
    agent.messages.clear()
    continue
```

---

## 参考リンク

- [Moonshot AI](https://www.moonshot.cn/)
- [Kimi K2 on Amazon Bedrock](https://aws.amazon.com/bedrock/kimi/)
