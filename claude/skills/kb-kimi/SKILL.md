---
name: kb-kimi
description: Kimi K2（Moonshot AI）特有の問題とワークアラウンド。Claudeモデルとの差異、リトライ処理等
user-invocable: true
---

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

## トラブルシューティング

### ツール呼び出しがreasoningText内に埋め込まれる

**症状**: ツールを呼び出そうとしたが、`current_tool_use`イベントが発火せず、フロントエンドに何も表示されずに終了する

**原因**: ツール呼び出しが`reasoningText`（思考プロセス）内にテキストとして埋め込まれ、実際のtool_useイベントに変換されない。`finish_reason: end_turn`で即座に終了する。

**ログの特徴**:
```json
"reasoningText": {
  "text": "...Web検索します。 <|tool_calls_section_begin|> <|tool_call_begin|> functions.web_search:0 <|tool_call_argument_begin|> {\"query\": \"...\"} <|tool_call_end|> <|tool_calls_section_end|>"
}
"finish_reason": "end_turn"
```

**解決策**: `reasoningText`内にツール呼び出しの痕跡がある場合もリトライ対象にする

```python
# resultイベントのreasoningContent処理部分
if hasattr(reasoning_text, 'text') and reasoning_text.text:
    text = reasoning_text.text
    # ツール呼び出しがテキストとして埋め込まれている場合を検出
    if "<|tool_call" in text or "functions.web_search" in text or "functions.output_slide" in text:
        tool_name_corrupted = True
        print(f"[WARN] Tool call found in reasoning text (retry ...)")
```

**ポイント**:
- `<|tool_call`や`functions.xxx`などの痕跡で検出
- ツール名破損と同じリトライロジックで対応可能
- 検出したら`tool_name_corrupted = True`にしてリトライ

---

### JSON引数内のマークダウンが抽出できない

**症状**: リトライしても同じ結果になり、結局何も応答せずに終了する。`reasoningText`内に`{"markdown": "---\\nmarp: true\\n..."}`のようなJSON引数が埋め込まれている。

**原因**: フォールバック用の抽出関数が直接的なマークダウン（`---\nmarp: true`）のみを抽出していた。JSON引数内のエスケープされた改行（`\\n`）は正規表現パターンにマッチしない。

**ログの特徴**:
```json
"reasoningText": {
  "text": "...スライドを作成します。 <|tool_call_argument_begin|> {\"markdown\": \"---\\nmarp: true\\ntheme: gradient\\n...\"} <|tool_call_end|>"
}
"finish_reason": "end_turn"
```

**解決策**: JSON引数からもマークダウンを抽出できるようにフォールバック関数を拡張

```python
def extract_marp_markdown_from_text(text: str) -> str | None:
    import re
    import json

    if not text:
        return None

    # ケース1: JSON引数内のマークダウンを抽出
    json_arg_pattern = r'<\|tool_call_argument_begin\|>\s*(\{[\s\S]*?\})\s*<\|tool_call_end\|>'
    json_match = re.search(json_arg_pattern, text)
    if json_match:
        try:
            data = json.loads(json_match.group(1))
            if isinstance(data, dict) and "markdown" in data:
                markdown = data["markdown"]
                if markdown and "marp: true" in markdown:
                    return markdown
        except json.JSONDecodeError:
            pass

    # ケース2: 直接的なマークダウンを抽出（既存の処理）
    if "marp: true" in text:
        pattern = r'(---\s*\nmarp:\s*true[\s\S]*?)(?:<\|tool_call|$)'
        match = re.search(pattern, text)
        if match:
            markdown = match.group(1).strip()
            markdown = re.sub(r'<\|[^>]+\|>', '', markdown)
            return markdown

    return None
```

**ポイント**:
- JSON引数内のマークダウンを優先的に抽出（より完全な形で取得できる）
- 直接的なマークダウンは後続のフォールバックとして維持
- `json.loads()`でエスケープが自動的に処理される（`\\n` → `\n`）

---

### ツール名破損とリトライ

**症状**: ツール呼び出し時にツール名が破損する（内部トークン `<|tooluse_end|>` 等が混入）

**例**: `web_search` が `web_search<|tooluse_end|><|ASSISTANT|><|reasoning|>` のようになる

**原因**: Kimi K2の内部トークンがツール名に混入するバグ

**解決策**: ツール名の破損を検出してリトライする

```python
VALID_TOOL_NAMES = {"web_search", "output_slide", "generate_tweet_url"}
MAX_RETRY_COUNT = 5

def is_tool_name_corrupted(tool_name: str) -> bool:
    """ツール名が破損しているかチェック"""
    if not tool_name:
        return False
    # 有効なツール名でなければ破損
    if tool_name not in VALID_TOOL_NAMES:
        return True
    # 内部トークンが混入していたら破損
    if "<|" in tool_name or "tooluse_" in tool_name:
        return True
    return False

# ストリーミング処理内で
retry_count = 0
while retry_count <= MAX_RETRY_COUNT:
    tool_name_corrupted = False
    stream = agent.stream_async(user_message)

    async for event in stream:
        if "current_tool_use" in event:
            tool_name = event["current_tool_use"].get("name", "")
            if is_tool_name_corrupted(tool_name):
                tool_name_corrupted = True
                continue  # 破損したツール呼び出しは無視
        # ...

    if tool_name_corrupted:
        retry_count += 1
        agent.messages.clear()  # 破損した履歴をクリア
        continue
    break
```

**ポイント**:
- 破損検出時は `agent.messages.clear()` で会話履歴をクリアしてからリトライ（破損した履歴を引き継がない）
- 最大リトライ回数を設定してループを防止
- Claudeモデルでは発生しないため、`model_type == "kimi"` でガード

---

### テキストストリームへのマークダウン混入

**症状**: ツールを呼ばずにテキストストリーム（`data`イベント）でマークダウンを直接出力する。チャット欄にマークダウンが表示され、プレビューには何も表示されない。

**解決策**: テキストをバッファリングしてマークダウンを検出、フォールバックとして抽出

```python
# ストリーミング処理内で
kimi_text_buffer = "" if model_type == "kimi" else None
kimi_skip_text = False

async for event in stream:
    if "data" in event:
        chunk = event["data"]
        if model_type == "kimi":
            kimi_text_buffer += chunk
            # マークダウン開始を検出したらテキスト送信をスキップ
            if not kimi_skip_text and "marp: true" in kimi_text_buffer.lower():
                kimi_skip_text = True
            if not kimi_skip_text:
                yield {"type": "text", "data": chunk}
        else:
            yield {"type": "text", "data": chunk}

# ストリーム終了後、バッファからマークダウンを抽出
if model_type == "kimi" and kimi_text_buffer:
    extracted = extract_marp_markdown_from_text(kimi_text_buffer)
    if extracted:
        fallback_markdown = extracted
```

**ポイント**:
- Kimi K2の場合のみテキストをバッファリング
- `marp: true`を検出したら以降のテキスト送信をスキップ（チャット欄への混入を防止）
- ストリーム終了後にバッファからマークダウンを抽出してフォールバックとして使用
- Claudeモデルはリアルタイム性を維持（バッファリングしない）

---

### `<think></think>`タグがテキストに混入

**症状**: チャット欄に`<think>...</think>`タグで囲まれた思考過程が表示される。

**原因**: Kimi K2 Thinkingは`reasoning`イベントとは別に、テキストストリーム（`data`イベント）に`<think>`タグを直接出力することがある。

**解決策**: ストリーミング処理中に`<think>`タグをリアルタイムでフィルタリング

```python
def remove_think_tags(text: str) -> str:
    """<think>...</think>タグを除去する"""
    import re
    return re.sub(r'<think>[\s\S]*?</think>', '', text)

# ストリーミング処理内で
kimi_in_think_tag = False  # <think>タグ内かどうか
kimi_pending_text = ""  # タグ検出用のペンディングバッファ

async for event in stream:
    if "data" in event:
        chunk = event["data"]
        kimi_pending_text += chunk

        # <think>タグ開始の検出
        while "<think>" in kimi_pending_text:
            before, _, after = kimi_pending_text.partition("<think>")
            if before:
                yield {"type": "text", "data": before}
            kimi_in_think_tag = True
            kimi_pending_text = after

        # </think>タグ終了の検出
        while "</think>" in kimi_pending_text:
            before, _, after = kimi_pending_text.partition("</think>")
            kimi_in_think_tag = False
            kimi_pending_text = after

        # タグ内でなければ出力（タグ断片は保留）
        if not kimi_in_think_tag:
            safe_end = len(kimi_pending_text)
            if "<" in kimi_pending_text:
                last_lt = kimi_pending_text.rfind("<")
                if len(kimi_pending_text) - last_lt <= 7:  # <think> は7文字
                    safe_end = last_lt
            if safe_end > 0:
                to_send = kimi_pending_text[:safe_end]
                kimi_pending_text = kimi_pending_text[safe_end:]
                if to_send:
                    yield {"type": "text", "data": to_send}
```

**ポイント**:
- ストリーミングで断片的に来るタグを正しく処理するためバッファリング
- `<think>`検出で思考モード開始、`</think>`で終了
- タグ断片（`<thi`など）を誤って出力しないよう末尾を保留
- ストリーム終了後にペンディングバッファの残りも処理

---

### Web検索後にスライドが生成されない

**症状**: Web検索を実行すると「Web検索完了」と表示された後、スライドが生成されずに終了する。「〜検索しておきます」というテキストは表示される。

**原因**: Web検索ツール実行後に、空のメッセージで`end_turn`している。

**ログの特徴**:
```json
"message":"","finish_reason":"end_turn"
```

既存のフォールバック条件（`not has_any_output`）では、検索前に「〜検索しておきます」というテキストが出力されるため `has_any_output = True` になり、フォールバックが発動しない。

**解決策**: `has_any_output`ではなく`web_search_executed`フラグで判定

```python
web_search_executed = False

# Web検索ツール実行時にフラグを立てる
if tool_name == "web_search":
    web_search_executed = True

# フォールバック条件を変更
if web_search_executed and not markdown_to_send and _last_search_result:
    # 検索結果を表示してユーザーに次のアクションを促す
    yield {"type": "text", "data": f"Web検索結果:\n\n{_last_search_result[:500]}...\n\n---\nスライドを作成しますか？"}
```

**ポイント**:
- テキスト出力の有無ではなく、Web検索が実行されたかどうかで判定
- Web検索後にスライドが生成されなかった場合、検索結果を表示してフォールバック

---

### ツール実行後に応答が表示されない

**症状**: Web検索等のツール実行後、UIに何も表示されず終了する

**原因**: Kimi K2 Thinkingは通常の`data`イベントではなく`reasoning`イベント（思考プロセス）を発火する。通常の`data`イベント処理では捕捉できない。

**解決策**: `reasoning`イベントを明示的に無視し、最終回答のみ表示する（上記「イベント処理」セクション参照）

---

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
