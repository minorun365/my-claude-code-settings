# 会話履歴の管理

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

### SlidingWindowConversationManager（履歴トリミング）

トークンコスト削減のため、古いメッセージを自動削除する組み込み機能。

```python
from strands import Agent
from strands.agent.conversation_manager import SlidingWindowConversationManager

agent = Agent(
    model=model,
    system_prompt=SYSTEM_PROMPT,
    tools=tools,
    conversation_manager=SlidingWindowConversationManager(window_size=6),
)
```

#### パラメータ

| パラメータ | デフォルト | 説明 |
|-----------|----------|------|
| `window_size` | 40 | 保持する最大**メッセージ数**（ターン数ではない） |
| `should_truncate_results` | True | ツール結果の圧縮を有効化 |
| `per_turn` | False | `False`: 完了後のみ / `True`: 毎回 / `int(N)`: N回ごとにトリミング |

#### window_size の意味

`window_size` は **Bedrock APIのメッセージ配列の要素数**。1つのメッセージが複数の content block（text, toolUse, toolResult）を持ちうるため、実際のテキスト量は window_size だけでは決まらない。

**典型的な1リクエストのメッセージ数（ツール2つ使用時）:**

```
[user]      ユーザーメッセージ          ... 1
[assistant] toolUse: web_search         ... 2
[user]      toolResult: 検索結果        ... 3
[assistant] toolUse: output_slide       ... 4
[user]      toolResult: スライド出力    ... 5
[assistant] 最終テキスト応答           ... 6
```

-> 1リクエスト = 6メッセージ -> `window_size=6` で約1リクエスト分を保持

#### トリミングアルゴリズム（2段階）

1. **フェーズ1: ツール結果の圧縮（優先）**
   - 古い toolResult の内容を `"The tool result was too large!"` に置換
   - メッセージ数は減らさない
   - 同じ toolResult を2回圧縮しない

2. **フェーズ2: メッセージの削除（最終手段）**
   - フェーズ1で不十分な場合、古いメッセージを削除
   - **toolUse/toolResult ペアの整合性を保持**（ペアが壊れない位置で削除）

#### per_turn パラメータの使い分け

```python
# デフォルト: エージェントループ完了後にのみトリミング
# -> 処理中は全メッセージが利用可能（品質重視）
SlidingWindowConversationManager(window_size=6)

# 毎回のモデル呼び出し前にトリミング
# -> ループが多いユースケースでトークン爆発を防止
SlidingWindowConversationManager(window_size=10, per_turn=True)

# N回ごとにトリミング（パフォーマンスバランス）
SlidingWindowConversationManager(window_size=10, per_turn=5)
```

#### per_turn=True と並列ツール実行の非互換性

**`per_turn=True` は、エージェントが複数ツールを並列発行するユースケースでは使用禁止。**

Strands Agents は並列ツール（例: `web_search` x2）の結果を1件ずつ個別にセッション履歴に追加する。`per_turn=True` だと各LLMコール前にトリミングが走り、以下の正のフィードバックループが発生する：

1. LLMが `web_search` x2 を並列発行
2. ツール結果1件目が履歴に追加 -> トリミング発生
3. 「検索結果が1件しかない」状態でLLMが呼ばれる
4. LLMは「情報不足」と判断して追加の `web_search` を発行
5. 1-4が連鎖 -> 1セッションで web_search が16-20回に増殖

さらに `output_slide` 等のツール結果が "The tool result was too large!" に圧縮され、ツールの正常動作も阻害される。

**推奨**: `per_turn=False`（デフォルト）のまま使用し、コスト削減はツール結果のサイズ制限（要約等）で対応する。

#### window_size チューニングの考え方

- フロントエンドが毎回最新コンテキスト（例: 生成済みMarkdown）を送信する設計なら、古い履歴は不要 -> 小さい window_size でOK
- `per_turn=False`（デフォルト）の場合、処理中のメッセージはトリミングされないため品質に影響しない
- トリミングの効果は **多ターンセッション** で最大化される

---

