# デバッグTips・MCP uvx・Cost Explorer

## デバッグTips

### CloudWatch Logs

Lambda/AgentCoreの問題を調査する際は、AWS CLIでログを確認：
```bash
aws logs tail /aws/bedrock-agentcore/runtime/RUNTIME_NAME --follow
```

### CloudWatch Logs Insights: タイムゾーン変換で時刻がズレる

**症状**: `datefloor(@timestamp + 9h, 1h)` でJSTに変換しているのに、結果の時刻がおかしい

**原因**: CloudWatch Logs Insightsの `datefloor(@timestamp + 9h, ...)` は挙動が不安定

**解決策**: UTCのまま集計してから、スクリプト側でJSTに変換する

```bash
# クエリはUTCで集計
--query-string 'stats count(*) by datefloor(@timestamp, 1h) as hour_utc | sort hour_utc asc'

# 結果をスクリプト側でJSTに変換
JST_HOUR=$(( (10#$UTC_HOUR + 9) % 24 ))
```

## MCP サーバー / plugin (uvx 系): Could not find the `uv` binary

**症状**: Claude Code 起動時に `uvx` 系の MCP / plugin-provided tool が接続エラーになる
- `aws-mcp`（aws-core プラグイン由来、`mcp-proxy-for-aws`）
- その他 `uvx` で起動する MCP 全般

`strands`（strands-agents-mcp-server）と `bedrock-agentcore-mcp-server` の raw MCP は 2026-06-21 に削除済み。これらの名前が出る場合は、古いセッション・古い settings・履歴ログを見ている可能性が高い。

`uvx --version` 実行時に以下のエラーが出る：
```
error: Could not find the `uv` binary at: /Users/<user>/.local/bin/uv
```

**原因**: `uvx`（`~/.local/bin/uvx`）は同ディレクトリの `uv` を呼び出すが、`uv` が Homebrew（`/opt/homebrew/bin/uv`）にしかインストールされておらず、パスが不一致

**診断手順**:
```bash
# 1. uvx の動作確認
uvx --version

# 2. uv の場所を検索
which uv
find /usr/local/bin /opt/homebrew/bin ~/.cargo/bin ~/.local/bin -name "uv" 2>/dev/null

# 3. プロセス確認（stdio 型 MCP が起動しているか）
ps aux | grep -E "mcp|uvx" | grep -v grep
```

**解決策**: Homebrew の `uv` へのシンボリックリンクを作成
```bash
ln -s /opt/homebrew/bin/uv ~/.local/bin/uv

# 確認
uvx --version  # → uvx x.x.x と表示されれば成功
```

その後 Claude Code を再起動すると uvx 系 MCP サーバーが全て復活する。

**補足**: `uv` と `uvx` はセットで動作する。`uvx` は内部で `uv` コマンドを呼び出して一時的な仮想環境を作成する仕組みのため、`uv` バイナリがないと全ての `uvx` 実行が失敗する。

## Cost Explorer: クレジット前後の正しい比較方法

### ✅ 正しい方法: GROUP BY RECORD_TYPE

```bash
aws ce get-cost-and-usage \
  --time-period Start=2026-04-01,End=2026-04-30 \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --group-by Type=DIMENSION,Key=RECORD_TYPE \
  --profile minorun365
```

RECORD_TYPE の主な値:

| RECORD_TYPE | 意味 |
|---|---|
| `Usage` | サービス利用料 |
| `Credit` | 適用クレジット（負の値） |
| `Support` | AWSサポートプラン料金 |
| `FlatRateSubscription` | フラット料金サブスクリプション |
| `Tax` | 税金 |

- **クレジット前** = Usage + Support + FlatRateSubscription の合計
- **クレジット後（実負担）** = 全 RECORD_TYPE の合計

アカウント別に見たい場合は `--filter` でアカウントを絞り、同じく `GROUP BY RECORD_TYPE` で取得する:

```bash
aws ce get-cost-and-usage \
  --time-period Start=2026-04-01,End=2026-04-30 \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --filter '{"Dimensions":{"Key":"LINKED_ACCOUNT","Values":["<アカウントID>"]}}' \
  --group-by Type=DIMENSION,Key=RECORD_TYPE \
  --profile minorun365
```

### ❌ やってはいけない間違い

| やりがちな方法 | 問題 |
|---|---|
| `GROUP BY SERVICE` でマイナス行を探す | Credit は SERVICE 次元に存在しない。クレジットが完全に欠落 |
| `UnblendedCost` vs `NetUnblendedCost` を比較 | どちらもクレジット適用後。差は出ない |
| `GROUP BY LINKED_ACCOUNT` の値をクレジット前と思う | ネット額（クレジット適用後）が返る |

### 重要な落とし穴

`GROUP BY LINKED_ACCOUNT` でアカウントが **~$0** に見えても、**クレジットで全額カバーされているだけで実際には使っている可能性がある**。
真の利用状況を確認するには必ず RECORD_TYPE でアカウント個別にクエリすること。

