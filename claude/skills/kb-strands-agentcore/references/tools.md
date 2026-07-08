# ツールの定義

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

### ツール駆動型の出力パターン

LLMの出力をフロントエンドでフィルタリングするのが難しい場合、出力専用のツールを作成してツール経由で出力させる方式が有効。

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

**メリット**:
- フロントエンドでのテキスト除去処理が不要
- ツール使用中のステータス表示が容易
- マークダウンがテキストストリームに混入しない

### 外部APIカスタムツール（追加パッケージ不要）

外部REST APIを呼ぶカスタムツールは `urllib.request`（標準ライブラリ）で実装すると、requirements.txtに追加パッケージ不要で済む。

```python
import json
import os
import urllib.request

from strands import tool

TAVILY_API_KEY = os.environ.get("TAVILY_API_KEY", "")

@tool
def web_search(query: str) -> str:
    """ウェブ検索を行い、最新の情報を取得します。

    Args:
        query: 検索クエリ

    Returns:
        検索結果のテキスト
    """
    req = urllib.request.Request(
        "https://api.tavily.com/search",
        data=json.dumps({
            "query": query,
            "max_results": 5,
            "search_depth": "basic",
            "include_answer": True,
        }).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {TAVILY_API_KEY}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    with urllib.request.urlopen(req, timeout=30) as resp:
        result = json.loads(resp.read().decode("utf-8"))

    parts = []
    if result.get("answer"):
        parts.append(f"【要約】\n{result['answer']}")
    for item in result.get("results", []):
        title = item.get("title", "")
        url = item.get("url", "")
        content = item.get("content", "")
        parts.append(f"■ {title}\n{url}\n{content}")

    return "\n\n".join(parts) if parts else "検索結果が見つかりませんでした。"
```

**ポイント**: `tavily-python` パッケージを使う方法もあるが、`urllib.request` なら追加依存なし。Docker/AgentCoreのビルド時間短縮にも有効。

---

