---
name: kb-ts-llm-app
description: LLMアプリトラブルシューティング。ストリーミング/Tavily/LINE/音声/エクスポート等
user-invocable: true
---

# LLMアプリ トラブルシューティング

LLMアプリケーション（バックエンド・連携API）で遭遇した問題と解決策を記録する。

## LINE Push Message: 429 月間メッセージ上限

**症状**: Push Message送信時に429エラー `{"message":"You have reached your monthly limit."}`

**原因**: 無料プラン（コミュニケーションプラン）の月200通上限に到達。SSEストリーミングで `contentBlockStop` ごとにPush Messageを送ると、1回の対話でツール通知+テキストブロック数だけ通数を消費する。

**解決策**: 最終テキストブロックのみ送信する方式に変更
- `contentBlockDelta` → バッファに蓄積
- `contentBlockStop` → `last_text_block` に保持（送信しない）
- ツール開始時 → バッファ破棄 + ステータスメッセージのみ送信
- SSE完了後 → `last_text_block` を1通だけ送信

**補足**: レート制限（2,000 req/s）とは別物。`Retry-After`ヘッダーは返されない。LINE公式は429を「リトライすべきでない4xx」に分類。

## LLM の曜日誤認識（strands_tools current_time）

**症状**: エージェントが日付の曜日を間違える（例: 月曜日を日曜日と回答）

**原因**: `strands_tools` の `current_time` は ISO 8601 形式を返すが、曜日情報が含まれない。LLM が自力で曜日を推測して間違える

**解決策**: カスタムツールで JST＋曜日を直接返す

```python
JST = timezone(timedelta(hours=9))
WEEKDAY_JA = ["月", "火", "水", "木", "金", "土", "日"]

@tool
def current_time() -> str:
    now = datetime.now(JST)
    weekday = WEEKDAY_JA[now.weekday()]
    return f"{now.year}年{now.month}月{now.day}日({weekday}) {now.strftime('%H:%M')} JST"
```

**教訓**: LLM に計算させず、ツール側で確定した情報を返す。

## BidiNovaSonicModel: 音声が早送り/遅再生になる

**症状**: Nova Sonic の音声出力が早送り（1.5倍速）のように聞こえる

**原因**: `provider_config["audio"]` のキー名が間違っている。SDK は `input_rate` / `output_rate` を期待するが、`input_sample_rate` / `output_sample_rate` と書くと無視されデフォルトの 16kHz が使われる

**解決策**: 正しいキー名を使う

```python
# NG: SDK が認識しないキー名（デフォルト 16kHz が使われる）
provider_config={
    "audio": {
        "input_sample_rate": 16000,
        "output_sample_rate": 24000,
    },
}

# OK: SDK が認識するキー名
provider_config={
    "audio": {
        "input_rate": 16000,
        "output_rate": 24000,
    },
}
```

**フロントエンド側**: `AudioBuffer` の `sampleRate` を `output_rate` と一致させる
```typescript
const SOURCE_SAMPLE_RATE = 24000;
const audioBuffer = ctx.createBuffer(1, int16Data.length, SOURCE_SAMPLE_RATE);
```

**教訓**: Strands SDK の `_resolve_provider_config` は dict merge するだけなので、未知のキーはエラーにならず静かに無視される。

## ストリーミング中のコードブロック除去が困難

**症状**: LLMがマークダウンをテキストとして出力すると、チャンク単位で```の検出が難しい

**原因**: SSEイベントはチャンク単位で来るため、```markdown と閉じの ``` が別チャンクになる

**解決策**: 出力専用のツールを作成し、ツール経由で出力させる
```python
@tool
def output_content(content: str) -> str:
    """生成したコンテンツを出力します。"""
    global _generated_content
    _generated_content = content
    return "出力完了"
```

システムプロンプトで「必ずこのツールを使って出力してください」と指示する。

## Tavily APIキーの環境変数

**症状**: AgentCore RuntimeでTavily検索が動かない

**原因**: 環境変数がランタイムに渡されていない

**解決策**: CDKで環境変数を設定
```typescript
const runtime = new agentcore.Runtime(stack, 'MyRuntime', {
  runtimeName: 'my-agent',
  agentRuntimeArtifact: artifact,
  environmentVariables: {
    TAVILY_API_KEY: process.env.TAVILY_API_KEY || '',
  },
});
```

sandbox起動時に環境変数を設定:
```bash
export TAVILY_API_KEY=$(grep TAVILY_API_KEY .env | cut -d= -f2) && npx ampx sandbox
```

## Tavily APIレートリミット: フォールバックが効かない

**症状**: 複数APIキーのフォールバックを実装したが、枯渇したキーで止まり次のキーに切り替わらない

**原因**: Tavilyのエラーメッセージが `"This request exceeds your plan's set usage limit"` で、`rate limit` や `quota` という文字列を含まない

**解決策**: エラー判定条件に `"usage limit"` を追加
```python
if "rate limit" in error_str or "429" in error_str or "quota" in error_str or "usage limit" in error_str:
    continue  # 次のキーで再試行
```

## SSEエクスポート: 大きいファイルのダウンロードが失敗する（PPTX/PDF）

**症状**: スライドのPPTXダウンロードで「PPTX生成に失敗しました」エラー。URL共有（HTML生成）は成功する

**原因**: SSEコネクションのアイドルタイムアウト。バックエンドでMarp CLI（Chromium）が変換中（数十秒〜120秒）、SSEストリームにデータが一切流れない。不安定なネットワークではアイドル期間にTCPコネクションがドロップする

**解決策**: 3層の対策
1. **バックエンドにSSE keep-alive**（最も効果的）: `asyncio.run_in_executor` でスレッド実行し、5秒ごとに `{"type": "progress"}` イベントをyield
2. **フロントエンドにリトライ**: 失敗時に1秒待って自動再試行（計2回）
3. **バックエンドにログ追加**: エクスポート処理の開始・完了・失敗を `print()` で記録

**教訓**: SSEで長時間処理を返す場合、処理中もkeep-aliveイベントを送信してコネクションを維持する
