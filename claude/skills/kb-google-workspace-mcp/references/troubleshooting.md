# Google Workspace MCP troubleshooting

## 目次

- トラブルシューティング
  - 🩺 まずは健康診断：`mcp__google-workspace__*` ツールが見当たらない／呼べないとき
  - 🚨 OAuth エラーが出たときの「最初の手」フローチャート
  - ❌ `Unable to parse range: <シート名>!A1:Z20`（シート名末尾スペース問題）
  - ❌ `error: Could not find the uv binary at: ~/.local/bin/uv`
  - ❌ `Cannot initiate OAuth flow - Port 8000 is already in use`
  - ❌ `Invalid or expired OAuth state parameter`
  - ❌ `Missing required parameter: redirect_uri` （Error 400: invalid_request）
  - ❌ `oauthlib.oauth2.rfc6749.errors.MismatchingStateError`
  - ❌ トークンが突然使えなくなった（7日後）

## トラブルシューティング

### 🩺 まずは健康診断：`mcp__google-workspace__*` ツールが見当たらない／呼べないとき

セッション内で Google Workspace のツールが ToolSearch にも出てこない・`Failed to connect` 状態に見えるときは、**OAuth より前のレイヤ**で壊れていることが多い。以下の順で診断する。

```bash
# 1. MCP サーバーの接続状態を確認（最初にやる）
claude mcp list 2>&1 | grep google-workspace
# → ✗ Failed to connect なら以下へ

# 2. workspace-mcp バイナリの存在確認
ls -la ~/.local/bin/workspace-mcp
# → No such file or directory なら uv tool install で再インストール
uv tool install workspace-mcp

# 3. credentials ディレクトリの存在確認
ls -la ~/.google_workspace_mcp/credentials/
# → 空 or No such file なら Step 8 のスタンドアロンスクリプトで再認証

# 4. ~/.claude.json に MCP 設定があるか確認
jq '.mcpServers["google-workspace"]' ~/.claude.json
# → null なら Step 7 から再設定
```

**よくある原因の特定：**

| 症状 | 原因 | 対処 |
|---|---|---|
| `claude mcp list` で `✗ Failed to connect` & バイナリが存在しない | `uv tool install` 未実行 / バイナリ消失 | `uv tool install workspace-mcp` |
| `claude mcp list` で `✗ Failed to connect` & バイナリは存在 | credentials 不足 or 設定不備 | credentials & `~/.claude.json` を確認 |
| MCP サーバーは接続済みだが ToolSearch にツールが出ない | **セッション起動時にツール一覧が固定**されているため、後から接続成功してもこのセッションでは見えない | **Claude Code セッション再起動が必須** |

> ⚠️ **教訓**：MCP サーバーを修復しても、起動済みの Claude Code セッションでは新しいツールは使えない。修復後は必ずセッションを再起動する。`/mcp` の再接続コマンドではツール一覧は更新されない。

---

### 🚨 OAuth エラーが出たときの「最初の手」フローチャート

ツール呼び出しで以下のどれかに該当するエラーが返ってきたら、**MCP ツールから返される URL で深追いせず、スタンドアロンスクリプト（Step 8）に直行**するのがいちばん事故が少ない。

| エラー文言 | 状況 | 最初の手 |
|---|---|---|
| `Cannot initiate OAuth flow - Port 8000 is already in use` | port 占有 | port 8000 を `lsof` で特定 → kill → Step 8 |
| `ACTION REQUIRED: Google Authentication Needed` | トークン無し or 失効 | Step 8（MCP の URL でも進められるが state 不一致リスクあり） |
| `Invalid or expired OAuth state parameter` | 複数プロセス間で state 不一致 | Step 8（MCP の URL は使わない） |
| `invalid_grant` 系 | リフレッシュトークン失効 | Step 8 |

> **教訓**：トークン切れの兆候が見えた時点で、Claude Code 上の MCP ツールから返ってくる OAuth URL を `open` で開く方式に頼ると、複数 Claude Code ウィンドウが立っていれば state 不一致で失敗する可能性がある。**スタンドアロンスクリプト方式（port 8080・トークンファイル直書き）が常に最も安全**。

---

### ❌ `Unable to parse range: <シート名>!A1:Z20`（シート名末尾スペース問題）

**原因:** Google Sheets API はシート名の完全一致を要求する。手動で作られたシートはタブ名末尾に**意図しない半角スペースが混入**していることがあり、想定通りの名前で range 指定すると `Unable to parse range` エラーになる。

**例:** 業務スプレッドシートでは `"202604(氏名) "`（末尾スペース1個）のように混在している。

**解決策:**

```python
# ❌ NG: シート名を勘で書く
range_name = "202604(氏名)!A1:Z20"

# ✅ OK: まず get_spreadsheet_info で正確な名前を取得
mcp__google-workspace__get_spreadsheet_info(
    user_google_email="<メールアドレス>",
    spreadsheet_id="..."
)
# → Sheets リストから正確なシート名（末尾スペース有無含む）を確認

# ✅ OK: シート名にスペースが含まれる場合はシングルクォートで括る
range_name = "'202604(氏名) '!A1:Z20"
```

> 💡 **運用ヒント**: 月次定常作業で同じスプレッドシートに繰り返しアクセスする場合は、初回に `get_spreadsheet_info` の結果から「自分が触る対象シートの正確な名前」を作業ログ（`tasks/.../YYYY-MM.md`）に記録しておくと、翌月も迷わない。

---

### ❌ `error: Could not find the uv binary at: ~/.local/bin/uv`

**原因:** `uvx` は自分と同じディレクトリに `uv` バイナリがあることを期待する。Homebrew でインストールした場合は `/opt/homebrew/bin/uv` にあるが、`~/.local/bin/uv` は存在しない。

**解決策:** `uv tool install workspace-mcp` で事前インストールし、`~/.claude.json` のコマンドを絶対パスに変更：
```
command: "~/.local/bin/workspace-mcp"
```

---

### ❌ `Cannot initiate OAuth flow - Port 8000 is already in use`

**原因（パターン1: workspace-mcp 自身）:** workspace-mcp 自体がポート 8000 で起動している。認証フロー開始時に別の HTTP サーバーを同じポートで立ち上げようとして失敗する。

**原因（パターン2: 過去の残骸プロセス）:** 過去の Claude Code セッションで起動した workspace-mcp の OAuth コールバックサーバー（python プロセス）が落ちずに残ったまま port 8000 を握り続けるケース。再起動しても解放されないことがある。

**⚠️ `/mcp` 再接続では解決しない:** Claude Code の `/mcp` スラッシュコマンドは MCP サーバーとの接続を張り直すだけで、credentials ファイルが無い（または期限切れ）の状態なら同じ OAuth flow を再試行 → 同じポート衝突で失敗する。無駄に再試行せず、すぐスタンドアロンスクリプトに移ること。

**解決策:**

```bash
# 1. ポート 8000 を握っているプロセスを特定
lsof -nP -iTCP:8000 -sTCP:LISTEN

# 2. 心当たりのある別用途（Web開発サーバ等）でなければ kill
kill <PID>  # 落ちなければ kill -9 <PID>

# 3. スタンドアロンスクリプト（Step 8）で再認証
```

> 💡 ステップ2でユーザー（みのるん）に確認するときは、`ps -p <PID> -o command=` でプロセスの正体を一緒に提示すると判断が早い。python プロセスで親が無いものはほぼ確実に MCP の残骸。

---

### ❌ `Invalid or expired OAuth state parameter`

**原因:** Claude Code のウィンドウを複数開いていると workspace-mcp プロセスが複数起動する。`start_google_auth` MCP ツールは呼び出したプロセス（例: PID A）のメモリに state を保存するが、コールバックはポート 8000 を握っている別プロセス（PID B）が受け取るため state が一致しない。

**解決策:** `start_google_auth` ツールは使わず、スタンドアロンスクリプト方式（Step 8）を使う。一度トークンファイルが `~/.google_workspace_mcp/credentials/` に保存されれば全プロセスが共有するので再発しない。

---

### ❌ `Missing required parameter: redirect_uri` （Error 400: invalid_request）

**原因:** `flow.authorization_url()` を単独で呼ぶと `redirect_uri` が URL に含まれない。`run_local_server()` が内部で `redirect_uri` をセットしてから URL を生成するため、先に `authorization_url()` を呼ぶと不完全な URL になる。

**解決策:** URL を手動生成したい場合は先に `flow.redirect_uri = "http://localhost:8080/"` をセットしてから `authorization_url()` を呼ぶ。
ただし後述の MismatchingStateError にも注意。

---

### ❌ `oauthlib.oauth2.rfc6749.errors.MismatchingStateError`

**原因:** `flow.authorization_url()` を手動で呼んだ後、さらに `flow.run_local_server()` を呼ぶと、`run_local_server` 内部でも `authorization_url()` が呼ばれ **state が2種類生成される**。ユーザーが古い state の URL で認証すると、`run_local_server` が待っている新しい state と一致せずエラーになる。

**解決策:** URL を自分で生成しない。バックグラウンド実行して `run_local_server` が出力する `"Please visit this URL..."` の行からURLを取得する：
```bash
grep "Please visit" /tmp/google_auth_output.txt \
  | sed 's/Please visit this URL to authorize this application: //'
```

---

### ❌ トークンが突然使えなくなった（7日後）

**原因:** Google Cloud の OAuth 同意画面を **Testing モード**で設定している場合、リフレッシュトークンが認証から **7日で失効**する。

**解決策:** スタンドアロンスクリプトを再実行して再認証する（Step 8）。本番移行（Publishing）すれば失効しなくなるが、ローカル個人用途なら Testing モードで7日ごとの再認証が現実的。

---

---
