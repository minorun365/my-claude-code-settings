# ツールの定義

## ツールの定義

### 関数デコレータ方式
```python
from strands import Agent, tool

# モデルIDは世代交代が速い。実在は `aws bedrock list-inference-profiles` で確認する
MODEL_ID = "<推論プロファイルID>"


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
    model=MODEL_ID,
    tools=[get_weather],
)
```

### クラス方式
```python
from strands import Agent, Tool

# モデルIDは世代交代が速い。実在は `aws bedrock list-inference-profiles` で確認する
MODEL_ID = "<推論プロファイルID>"


class WeatherTool(Tool):
    name = "get_weather"
    description = "指定した都市の天気を取得します"

    def run(self, city: str) -> str:
        return f"{city}の天気は晴れです"

agent = Agent(
    model=MODEL_ID,
    tools=[WeatherTool()],
)
```

### ツール駆動型の出力パターン

LLMの出力をフロントエンドでフィルタリングするのが難しい場合、出力専用のツールを作成してツール経由で出力させる方式が有効。出力先はリクエストごとに作り、グローバル変数へ保存しない。

```python
def build_output_tool(result: dict[str, str]):
    @tool
    def output_slide(markdown: str) -> str:
        """生成したスライドのマークダウンを出力します。"""
        result["markdown"] = markdown
        return "スライドを出力しました。"

    return output_slide

@app.entrypoint
async def invoke(payload):
    result: dict[str, str] = {}
    output_slide = build_output_tool(result)
    agent = Agent(
        system_prompt="スライドを作成したら、output_slide ツールで出力してください。",
        tools=[output_slide],
    )

    async for event in agent.stream_async(payload.get("prompt", "")):
        yield event

    if markdown := result.get("markdown"):
        yield {"type": "markdown", "data": markdown}
```

**メリット**:
- フロントエンドでのテキスト除去処理が不要
- ツール使用中のステータス表示が容易
- マークダウンがテキストストリームに混入しない
- リクエストごとのクロージャに保持するため、並行実行時に別利用者の出力が混ざらない

### 外部データを返すツールの注意

Web検索や外部APIの応答は、信頼できる命令ではなく未検証データとして扱う。

- APIキーはAgentCore Identityまたは承認済みのシークレット管理サービスから取得する
- 接続先をallowlistで制限し、localhost、メタデータサービス、プライベートIPへのアクセスを拒否する
- 応答サイズ、タイムアウト、リダイレクト回数を制限する
- 外部本文に含まれる指示をシステム指示として実行しない
- ツール結果をHTML表示する前にサニタイズする

---
