# Strands Agents ナレッジ

AWS が提供する AI エージェントフレームワーク「Strands Agents」に関する学びを記録する。

## 基本情報

- 公式: https://strandsagents.com/
- GitHub: https://github.com/strands-agents/strands-agents
- Python 3.10以上が必要

## インストール

```bash
# pip
pip install strands-agents

# uv
uv add strands-agents
```

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
```python
# Claude Sonnet 4.5（推奨）
model = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"

# Claude Haiku 4.5（高速・低コスト）
model = "us.anthropic.claude-haiku-4-5-20251001-v1:0"
```

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

## ツールの定義

### 関数デコレータ方式
```python
from strands import Agent, tool

@tool
def get_weather(city: str) -> str:
    """指定した都市の天気を取得します。

    Args:
        city: 都市名

    Returns:
        天気情報
    """
    return f"{city}の天気は晴れです"

agent = Agent(
    model="us.anthropic.claude-sonnet-4-5-20250929-v1:0",
    tools=[get_weather],
)
```

### クラス方式
```python
from strands import Agent, Tool

class WeatherTool(Tool):
    name = "get_weather"
    description = "指定した都市の天気を取得します"

    def run(self, city: str) -> str:
        return f"{city}の天気は晴れです"

agent = Agent(
    model="us.anthropic.claude-sonnet-4-5-20250929-v1:0",
    tools=[WeatherTool()],
)
```

## 会話履歴の管理

```python
from strands import Agent

agent = Agent(model="us.anthropic.claude-sonnet-4-5-20250929-v1:0")

# 会話を継続
response1 = agent("私の名前は太郎です")
response2 = agent("私の名前は何ですか？")  # 「太郎」と答える

# 履歴をクリア
agent.clear_history()
```

## Bedrock AgentCore との統合

### 基本構造
```python
from bedrock_agentcore import BedrockAgentCoreApp
from strands import Agent

app = BedrockAgentCoreApp()
agent = Agent(model="us.anthropic.claude-sonnet-4-5-20250929-v1:0")

@app.entrypoint
async def invoke(payload):
    prompt = payload.get("prompt", "")
    stream = agent.stream_async(prompt)
    async for event in stream:
        yield event

if __name__ == "__main__":
    app.run()  # ポート8080でリッスン
```

### 必要な依存関係
```
# requirements.txt
bedrock-agentcore
strands-agents
tavily-python  # Web検索が必要な場合
```

**注意**: fastapi/uvicorn は不要（bedrock-agentcore SDKに内包）

### セッションIDでAgentを管理（複数ユーザー対応）

AgentCoreで複数ユーザーの会話履歴を保持する場合、セッションIDごとにAgentインスタンスを管理する：

```python
from strands import Agent

# セッションごとのAgentインスタンスを管理
_agent_sessions: dict[str, Agent] = {}

def get_or_create_agent(session_id: str | None) -> Agent:
    """セッションIDに対応するAgentを取得または作成"""
    # セッションIDがない場合は新規Agentを作成（履歴なし）
    if not session_id:
        return Agent(
            model="us.anthropic.claude-sonnet-4-5-20250929-v1:0",
            system_prompt="...",
            tools=[...],
        )

    # 既存のセッションがあればそのAgentを返す
    if session_id in _agent_sessions:
        return _agent_sessions[session_id]

    # 新規セッションの場合はAgentを作成して保存
    agent = Agent(
        model="us.anthropic.claude-sonnet-4-5-20250929-v1:0",
        system_prompt="...",
        tools=[...],
    )
    _agent_sessions[session_id] = agent
    return agent

@app.entrypoint
async def invoke(payload):
    session_id = payload.get("session_id")
    agent = get_or_create_agent(session_id)
    # ...
```

**注意**: コンテナ再起動でセッションは消える（メモリ管理）。永続化が必要な場合はDynamoDB等を検討。

## ツール駆動型の出力パターン

LLMの出力をフロントエンドでフィルタリングするのが難しい場合、出力専用のツールを作成してツール経由で出力させる方式が有効。

### 例：マークダウン出力ツール
```python
# グローバル変数で出力を保持
_generated_markdown: str | None = None

@tool
def output_slide(markdown: str) -> str:
    """生成したスライドのマークダウンを出力します。

    Args:
        markdown: Marp形式のマークダウン全文

    Returns:
        出力完了メッセージ
    """
    global _generated_markdown
    _generated_markdown = markdown
    return "スライドを出力しました。"

agent = Agent(
    model="us.anthropic.claude-sonnet-4-5-20250929-v1:0",
    system_prompt="スライドを作成したら、必ず output_slide ツールを使って出力してください。",
    tools=[output_slide],
)
```

### AgentCoreでのツール使用イベント送信
```python
@app.entrypoint
async def invoke(payload):
    global _generated_markdown
    _generated_markdown = None

    stream = agent.stream_async(payload.get("prompt", ""))
    async for event in stream:
        if "data" in event:
            yield {"type": "text", "data": event["data"]}
        elif "current_tool_use" in event:
            tool_name = event["current_tool_use"].get("name", "unknown")
            yield {"type": "tool_use", "data": tool_name}

    if _generated_markdown:
        yield {"type": "markdown", "data": _generated_markdown}
```

**メリット**:
- フロントエンドでのテキスト除去処理が不要
- ツール使用中のステータス表示が容易
- マークダウンがテキストストリームに混入しない

## システムプロンプト設計

### 例：スライド生成エージェント
```python
system_prompt = """
あなたは「パワポ作るマン」、プロフェッショナルなスライド作成AIアシスタントです。

## 役割
ユーザーの指示に基づいて、Marp形式のマークダウンでスライドを作成・編集します。

## スライド作成ルール
- フロントマターには `marp: true` を含める
- スライド区切りは `---` を使用
- 1枚目はタイトルスライド
- 箇条書きは1スライドあたり3〜5項目
- 適度に絵文字を使用

## 出力形式
スライドを生成したら、マークダウン全文を ```markdown コードブロックで出力してください。
"""

agent = Agent(
    model="us.anthropic.claude-sonnet-4-5-20250929-v1:0",
    system_prompt=system_prompt,
)
```

## トラブルシューティング

### AWS認証エラー
`aws login` で認証した場合、`botocore[crt]` が必要：
```bash
uv add 'botocore[crt]'
```

### モデルが見つからない
クロスリージョン推論のモデルID（`us.` プレフィックス）を使用しているか確認。
リージョンによって利用可能なモデルが異なる。

### ストリーミングが動かない
`stream()` と `stream_async()` を環境に合わせて使い分ける：
- 同期コンテキスト → `stream()`
- 非同期コンテキスト（async/await） → `stream_async()`

## 参考リンク

- [Strands Agents 公式ドキュメント](https://strandsagents.com/)
- [GitHub リポジトリ](https://github.com/strands-agents/strands-agents)
- [Bedrock AgentCore 統合ガイド](https://docs.aws.amazon.com/bedrock/latest/userguide/agents-agentcore.html)
