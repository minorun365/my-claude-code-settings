# Agent作成・実行方法・イベントタイプ

## Agent作成

### 基本構造
```python
from strands import Agent

agent = Agent(
    model="us.anthropic.claude-sonnet-4-5-20250929-v1:0",
    system_prompt="あなたはアシスタントです",
)
```

### 利用可能なモデル（Bedrock）

#### デフォルトモデル

Strands Agents Python SDK (v1.35.1+) のデフォルトは **`global.anthropic.claude-sonnet-4-6`** (Claude Sonnet 4.6)。

```python
from strands import Agent

# デフォルト（global. プロファイル使用）
agent = Agent()
print(agent.model.config["model_id"])  # global.anthropic.claude-sonnet-4-6
```

`global.` プロファイルは全Bedrockリージョンで利用可能で、AWS側がトラフィックを最適なリージョンにルーティングする。

#### クロスリージョン推論プロファイル

明示的にリージョン別プロファイルを指定する場合：

| リージョン群 | プレフィックス | 例 |
|------------|--------------|---|
| US（us-east-1, us-west-2 等） | `us.` | `us.anthropic.claude-sonnet-4-6` |
| EU（eu-west-1 等） | `eu.` | `eu.anthropic.claude-sonnet-4-6` |
| 日本（ap-northeast-1, ap-northeast-3） | `jp.` | `jp.anthropic.claude-sonnet-4-6` |
| オーストラリア（ap-southeast-2, ap-southeast-4） | `au.` | `au.anthropic.claude-sonnet-4-6` |
| 全リージョン | `global.` | `global.anthropic.claude-sonnet-4-6` |

```python
from strands import Agent
from strands.models import BedrockModel

# 東京リージョンで jp. プロファイルを明示指定
model = BedrockModel(
    region_name="ap-northeast-1",
    model_id="jp.anthropic.claude-sonnet-4-6"
)
agent = Agent(model=model)
```

**注意**: Sonnet 4.5 以前には `apac.` プロファイルが存在したが、Sonnet 4.6 では廃止され `jp.`/`au.` に分離。韓国・シンガポール・インド等は `global.` のみ対応。

**注意（呼び出し元リージョンの制約）**: プロファイルのプレフィックスは**クライアントのリージョンと揃っていないと使えない**。us-east-1 のクライアントから `jp.` を指定すると `ValidationException: The provided model identifier is invalid` になる。上のコード例のように `region_name` と `model_id` を必ずセットで切り替える。地理フォールバックを組むときは、フォールバック先のリージョンぶんも IAM で許可されているかを併せて確認する。

#### モデルIDの確認方法（AWS CLI）

```bash
# ap-northeast-1 で利用可能な Sonnet 4.6 プロファイルを確認
aws bedrock list-inference-profiles \
  --region ap-northeast-1 \
  --query 'inferenceProfileSummaries[?contains(inferenceProfileId, `sonnet-4-6`)].{id:inferenceProfileId,name:inferenceProfileName}' \
  --output table

# 実際に呼び出して動作確認
aws bedrock-runtime converse \
  --model-id "global.anthropic.claude-sonnet-4-6" \
  --messages '[{"role":"user","content":[{"text":"hi"}]}]' \
  --region ap-northeast-1
```

---

## 実行方法

### 同期実行
```python
result = agent(prompt)
print(result)
```

### 非同期実行
```python
result = await agent.invoke_async(prompt)
```

### ストリーミング（同期）
```python
for event in agent.stream(prompt):
    if "data" in event:
        print(event["data"], end="", flush=True)
```

### ストリーミング（非同期）
```python
async for event in agent.stream_async(prompt):
    if "data" in event:
        print(event["data"], end="", flush=True)
```

---

## イベントタイプ

ストリーミング時に受け取るイベント：

| イベント | 説明 |
|---------|------|
| `data` | テキストチャンク（LLMの出力） |
| `current_tool_use` | ツール使用情報 |
| `result` | 最終結果 |

```python
async for event in agent.stream_async(prompt):
    if "data" in event:
        # テキストチャンク
        print(event["data"], end="")
    elif "current_tool_use" in event:
        # ツール使用中
        tool_info = event["current_tool_use"]
        print(f"Using tool: {tool_info['name']}")
    elif "result" in event:
        # 完了
        final_result = event["result"]
```

### current_tool_use の input はストリーミング中は文字列型

`current_tool_use` イベントの `input` フィールドは、ストリーミング中は**不完全なJSON文字列**として徐々に構築される。辞書型を期待している場合はJSONパースが必要：

```python
elif "current_tool_use" in event:
    tool_info = event["current_tool_use"]
    tool_name = tool_info.get("name", "unknown")
    tool_input = tool_info.get("input", {})

    # inputが文字列の場合はJSONパースを試みる
    if isinstance(tool_input, str):
        try:
            import json
            tool_input = json.loads(tool_input)
        except json.JSONDecodeError:
            pass  # パースできない場合はそのまま（不完全なJSON）

    # パース成功時のみ辞書として扱える
    if isinstance(tool_input, dict) and "query" in tool_input:
        print(f"Search query: {tool_input['query']}")
```

**ポイント**: ストリーミング中はイベントが複数回発火し、`{"query"` -> `{"query": "検索` -> `{"query": "検索ワード"}` のように徐々に完成する。完全なJSONになったタイミングでのみパースが成功する。

**重要: バックエンドで重複スキップしてはいけない**

`current_tool_use` の重複イベントをバックエンドで `continue` してはいけない。理由：
- 最初のチャンクの `input` は不完全なJSON文字列（例: `"{\"qu"`）
- JSONパースが失敗し、`query` 等の必要なパラメータが取得できない
- 後続チャンク（パラメータが完成したもの）がスキップされ、イベントが一切フロントに送信されなくなる

重複の吸収はフロントエンド側（`hasInProgress` チェック等）で行うのが正しい。

**同じ罠は「上限で打ち切る」実装でも踏む**

通知が増えすぎないよう `if count <= 6:` のような上限を付けるとき、**カウンターをイベント単位で
増やすと、JSONとして読めない途中経過でも枠を消費する**。読める形になったときには使い切っていて、
通知が一度も出ない。しかもカウンターがストリーム全体で共有されていると、2回目以降のツール呼び出しは
確実に出なくなる。

```python
# NG: スナップショットの数を数えている（読めなかった回も1件と数える）
event_count += 1
if event_count <= 6 and isinstance(tool_input, dict) and "query" in tool_input:
    yield {...}

# OK: 実際に画面へ出した回数を数える。既出の途中までなら出し直さない
query = tool_input.get("query", "") if isinstance(tool_input, dict) else ""
if query and not any(a.startswith(query) for a in announced):
    announced.append(query)
    notice_count += 1
    if notice_count <= 6:
        yield {...}
```

**数えてよいのは「読めたもの」だけ。** イベントの回数を数えた時点で、
上の「バックエンドで重複スキップ」と同じ壊れ方になる。

```python
# NG: バックエンドで重複スキップ -> 最初のチャンク（input不完全）のみ処理される
if tool_name == last_tool_name:
    continue  # 2回目以降のチャンク（inputが完全）がスキップされる！
last_tool_name = tool_name

# OK: 重複スキップせず、条件に合うときだけyield（フロント側で重複吸収）
if tool_name == "web_search":
    if isinstance(tool_input, dict) and "query" in tool_input:
        yield {"type": "tool_use", "data": tool_name, "query": tool_input["query"]}
    # queryが不完全なチャンクではyieldしない -> 完成したチャンクでyieldされる
else:
    yield {"type": "tool_use", "data": tool_name}
```

---

