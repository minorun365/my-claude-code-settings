# イベント処理

## イベント処理

### reasoningイベント（思考プロセス）

Kimi K2 Thinkingは通常の`data`イベントに加えて`reasoning`イベント（思考プロセス）を発火する。

```python
async for event in agent.stream_async(prompt):
    # 思考プロセスは無視（最終回答のみ表示する場合）
    if event.get("reasoning"):
        continue

    if "data" in event:
        yield {"type": "text", "data": event["data"]}
    elif "result" in event:
        result = event["result"]
        if hasattr(result, 'message') and result.message:
            for content in getattr(result.message, 'content', []):
                # reasoningContent も無視
                if hasattr(content, 'reasoningContent'):
                    continue
                if hasattr(content, 'text') and content.text:
                    yield {"type": "text", "data": content.text}
```

**思考プロセスを表示したい場合**は`reasoningText`イベントを処理する。

---

