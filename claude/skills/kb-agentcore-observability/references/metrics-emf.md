# EMF メトリクス

## EMF（Embedded Metric Format）メトリクス

Strands Agentsは自動的にEMF形式でトークンメトリクスを出力する。ログストリーム `otel-rt-logs` にJSON形式で記録される。

**メトリクス名一覧:**
- `strands.event_loop.input.tokens` / `strands.event_loop.output.tokens`
- `strands.event_loop.cache_read.input.tokens` / `strands.event_loop.cache_write.input.tokens`
- `strands.event_loop.latency` / `strands.model.time_to_first_token`

**EMFのデータ形式はヒストグラム:**

```json
{
  "strands.event_loop.input.tokens": {
    "Values": [576.81, 2571.17, 7272.37],
    "Counts": [1.0, 1.0, 1.0],
    "Count": 3,
    "Sum": 10344,
    "Max": 7197,
    "Min": 582
  }
}
```

- `Count`: 1回のエージェント呼び出し内のモデルコール回数（≒ターン数）
- `Sum`: セッション合計トークン
- `Max`/`Min`: 単一ターンの最大/最小値
- `Values`: 近似値（ヒストグラムバケット境界）。**正確な値は Sum/Max/Min を使う**

**CloudWatch Log Insights での分析:**

```
# EMFログの検索
filter @message like /strands.event_loop.input.tokens/
| fields @message, @timestamp
| limit 200
```

**注意**: Log Insights の `parse` + `stats pct()` では EMF ヒストグラムの値を正しく集計できない。Python等で JSON をパースして `Sum`/`Max`/`Min` を直接抽出する方が正確。

---

