# Google Workspace MCP setup and OAuth

## 目次

- MCP サーバー選定
- OAuth 設定手順（2025〜2026年版・最新 UI 対応）
  - Step 1: Google Cloud プロジェクト作成
  - Step 2: API を一括有効化
  - Step 3: Branding 設定（旧「OAuth 同意画面」）
  - Step 4: Audience 設定（テストユーザー追加）
  - Step 5: OAuth クライアント ID 作成
  - Step 6: 認証情報の配置
  - Step 7: Claude Code への MCP 追加
  - Step 8: 初回認証（スタンドアロンスクリプト方式）
    - Codex で OAuth callback server が port 8000 競合した場合
    - Codex で OAuth 認証URLが出たときの運用（重要）
    - 個人アカウントなど、特定の Chrome プロファイルで認証したい場合
- セキュリティ注意点
- Gmail API スコープ一覧

## MCP サーバー選定

| サーバー | 特徴 | 用途 |
|---------|------|------|
| [taylorwilsdon/google_workspace_mcp](https://github.com/taylorwilsdon/google_workspace_mcp) | Gmail/Drive/Calendar/Docs/Sheets/Slides 対応。スター数最多（1,100+）。PyPI パッケージ名は **`workspace-mcp`**（`google-workspace-mcp` は別作者の別物） | **基本推奨** |
| [aaronsb/google-workspace-mcp](https://github.com/aaronsb/google-workspace-mcp) | マルチアカウント管理ツール内蔵。会話中にアカウント切り替え可能 | マルチアカウント強化したい場合 |
| [GongRzhe/Gmail-MCP-Server](https://github.com/GongRzhe/Gmail-MCP-Server) | Gmail 専用。ブラウザ自動起動で初回認証が簡単 | Gmail のみ |

## OAuth 設定手順（2025〜2026年版・最新 UI 対応）

> ⚠️ 旧「OAuth 同意画面」メニューは廃止。新しい **「Google Auth Platform」** から設定する。

### Step 1: Google Cloud プロジェクト作成

1. https://console.cloud.google.com にアクセス（個人 Google アカウントでログイン）
2. 上部「プロジェクトを選択」→「新しいプロジェクト」→ 名前入力（例: `gmail-mcp`）→「作成」

### Step 2: API を一括有効化

gcloud CLI を使うと一括で高速に有効化できる：

```bash
gcloud services enable \
  gmail.googleapis.com \
  drive.googleapis.com \
  calendar-json.googleapis.com \
  docs.googleapis.com \
  sheets.googleapis.com \
  slides.googleapis.com \
  --project=YOUR_PROJECT_ID
```

プロジェクト ID は Cloud Console 上部「プロジェクトを選択」で確認。
GUI から有効化する場合は「APIs & Services > Library」で各 API を検索して「Enable」。

### Step 3: Branding 設定（旧「OAuth 同意画面」）

左メニュー「**Google Auth Platform**」→「**Branding**」
- アプリ名: `gmail-mcp`（任意）
- サポート用メール: 自分のメアドを選択
- 「Save」

### Step 4: Audience 設定（テストユーザー追加）

左メニュー「Google Auth Platform」→「**Audience**」
- User Type: **External**（個人 Gmail アカウントはこちら）
  - Internal は Google Workspace 組織アカウントのみ選択可能
- 公開ステータス: **Testing**（個人ローカル利用はこれで十分）
- 「Test users」セクション →「+ Add users」
  - **この MCP で使うアカウントのメールアドレスを追加する**
  - 最大100アカウントまで登録可能
- 「Save」

> ⚠️ **Testing モードの注意点**: OAuth トークン（リフレッシュトークン含む）が認証から **7日で失効**する。週1回程度の再認証が必要。

### Step 5: OAuth クライアント ID 作成

左メニュー「Google Auth Platform」→「**Clients**」→「**Create Client**」
- Application type: **Desktop app**
- Name: `gmail-mcp-client`（任意）
- 「Create」→ 表示された Client ID / Client secret を確認
- **「Download JSON」で今すぐダウンロード**（2025年6月以降、作成後は再取得不可）

### Step 6: 認証情報の配置

```bash
mkdir -p ~/.config/google-workspace-mcp

# ダウンロードした JSON を配置
mv ~/Downloads/client_secret_xxx.json ~/.config/google-workspace-mcp/gcp-oauth.keys.json

# セキュリティのためパーミッション制限
chmod 600 ~/.config/google-workspace-mcp/gcp-oauth.keys.json
```

### Step 7: Claude Code への MCP 追加

まず `workspace-mcp` をインストールしてバイナリを `~/.local/bin/` に配置する：

```bash
uv tool install workspace-mcp
```

次に `~/.claude.json` に MCP 設定を追加する：

```bash
# ~/.claude.json に追記する方法（正しい保存先）
# ※ settings.json / settings.local.json の mcpServers は Claude Code では無効！
# ※ 正しい保存先は ~/.claude.json（claude mcp add コマンドが書き込む場所）

CLIENT_ID=$(jq -r '.installed.client_id' ~/.config/google-workspace-mcp/gcp-oauth.keys.json)
CLIENT_SECRET=$(jq -r '.installed.client_secret' ~/.config/google-workspace-mcp/gcp-oauth.keys.json)
jq --arg id "$CLIENT_ID" --arg secret "$CLIENT_SECRET" \
  '.mcpServers["google-workspace"] = {type: "stdio", command: "~/.local/bin/workspace-mcp", args: ["--tool-tier", "complete"], env: {GOOGLE_OAUTH_CLIENT_ID: $id, GOOGLE_OAUTH_CLIENT_SECRET: $secret}}' \
  ~/.claude.json > /tmp/claude.tmp && mv /tmp/claude.tmp ~/.claude.json
```

**⚠️ 重要な落とし穴（実際にハマった）：**
- `settings.json` / `settings.local.json` は権限・モデル・フック用であり、**MCP 設定は無効**
- MCP の正しい保存先は **`~/.claude.json`**（全プロジェクト共通）
- PyPI に `google-workspace-mcp`（Arclio製・バグあり）と `workspace-mcp`（taylorwilsdon製・正規）の2つが存在
- `google-workspace-mcp` は v2.0.1 で `asyncio.run()` に同期関数を渡すバグがあり起動不可
- 正しいパッケージ名は **`workspace-mcp`**（`uvx workspace-mcp` で起動）
- **`uvx workspace-mcp` は `~/.local/bin/uv` を探してエラーになる場合がある**。`uv tool install` でインストール後に絶対パス `~/.local/bin/workspace-mcp` を指定するのが確実
- 環境変数名: `GOOGLE_OAUTH_CLIENT_ID` / `GOOGLE_OAUTH_CLIENT_SECRET`（`GOOGLE_CLIENT_ID` ではない）
- `--tool-tier complete` で Gmail/Drive/Calendar/Docs/Sheets/Slides/Tasks 等 12 サービス・139 ツール有効化

### Step 8: 初回認証（スタンドアロンスクリプト方式）

> ⚠️ **`start_google_auth` MCP ツールは使わない！**
> Claude Code のウィンドウを複数開いていると workspace-mcp プロセスが複数起動する。
> OAuth state は各プロセスのメモリに個別保存されるため、state を保存したプロセスと
> port 8000 でコールバックを受け取るプロセスが食い違い → `Invalid or expired OAuth state parameter` エラーが発生する。

代わりに以下のスタンドアロンスクリプトを実行する（port 8080 を使うので衝突しない）：

```bash
# スクリプトを作成
cat > /tmp/get_google_token.py << 'EOF'
import json, os, socketserver
# port 8080 の TIME_WAIT 残留で OSError: [Errno 48] Address already in use を回避
socketserver.TCPServer.allow_reuse_address = True
from google_auth_oauthlib.flow import InstalledAppFlow

USER_EMAIL = "<メールアドレス>"
OAUTH_KEYS_PATH = os.path.expanduser("~/.config/google-workspace-mcp/gcp-oauth.keys.json")
CREDS_DIR = os.path.expanduser("~/.google_workspace_mcp/credentials")

SCOPES = [
    "https://www.googleapis.com/auth/gmail.readonly",
    "https://www.googleapis.com/auth/gmail.send",
    "https://www.googleapis.com/auth/gmail.compose",
    "https://www.googleapis.com/auth/gmail.modify",
    "https://www.googleapis.com/auth/gmail.labels",
    "https://www.googleapis.com/auth/gmail.settings.basic",
    "https://www.googleapis.com/auth/drive",
    "https://www.googleapis.com/auth/drive.readonly",
    "https://www.googleapis.com/auth/drive.file",
    "https://www.googleapis.com/auth/documents",
    "https://www.googleapis.com/auth/documents.readonly",
    "https://www.googleapis.com/auth/spreadsheets",
    "https://www.googleapis.com/auth/spreadsheets.readonly",
    "https://www.googleapis.com/auth/presentations",
    "https://www.googleapis.com/auth/presentations.readonly",
    "https://www.googleapis.com/auth/calendar",
    "https://www.googleapis.com/auth/calendar.readonly",
    "https://www.googleapis.com/auth/calendar.events",
    "https://www.googleapis.com/auth/contacts",
    "https://www.googleapis.com/auth/contacts.readonly",
    "https://www.googleapis.com/auth/tasks",
    "https://www.googleapis.com/auth/tasks.readonly",
    "https://www.googleapis.com/auth/chat.messages",
    "https://www.googleapis.com/auth/chat.messages.readonly",
    "https://www.googleapis.com/auth/chat.spaces",
    "https://www.googleapis.com/auth/chat.spaces.readonly",
    "openid",
    "https://www.googleapis.com/auth/userinfo.email",
    "https://www.googleapis.com/auth/userinfo.profile",
]

with open(OAUTH_KEYS_PATH) as f:
    client_config = json.load(f)

flow = InstalledAppFlow.from_client_config(client_config, SCOPES)
credentials = flow.run_local_server(port=8080, access_type="offline", prompt="consent", open_browser=True)

os.makedirs(CREDS_DIR, exist_ok=True)
creds_data = {
    "token": credentials.token,
    "refresh_token": credentials.refresh_token,
    "token_uri": credentials.token_uri,
    "client_id": credentials.client_id,
    "client_secret": credentials.client_secret,
    "scopes": list(credentials.scopes) if credentials.scopes else SCOPES,
    "expiry": credentials.expiry.isoformat() if credentials.expiry else None,
}
creds_path = os.path.join(CREDS_DIR, f"{USER_EMAIL}.json")
with open(creds_path, "w") as f:
    json.dump(creds_data, f, indent=2)
os.chmod(creds_path, 0o600)
print(f"✅ 保存完了: {creds_path}")
EOF

# workspace-mcp の Python 環境で実行
~/.local/share/uv/tools/workspace-mcp/bin/python /tmp/get_google_token.py
```

ブラウザが自動で開くので Google ログイン → 許可 → ターミナルに「✅ 保存完了」が表示されれば完了。

**トークンの保存先:** `~/.google_workspace_mcp/credentials/EMAIL.json`（全 workspace-mcp プロセスが共有して読み込む）

#### Codex で OAuth callback server が port 8000 競合した場合

Codex から `mcp__google_workspace__search_gmail_messages` などを個人アカウント用に使ったとき、再接続で次のエラーが出ることがある。

```text
Cannot initiate OAuth flow - callback server unavailable (Port 8000 is already in use on localhost. Cannot start minimal OAuth server.)
```

これは別の Claude Code / Codex セッションで起動した `workspace-mcp` が `localhost:8000` を保持している状態。まず占有プロセスを確認する。

```bash
lsof -nP -iTCP:8000 -sTCP:LISTEN
ps -axo pid,ppid,command | rg 'workspace-mcp|8000|<PID>'
```

`workspace-mcp --tool-tier complete` が原因で、ユーザーから停止許可が明示されている場合は対象 PID を `kill <PID>` してから同じ MCP ツールを再実行する。保存済み credential が有効なら、ブラウザ認証なしで個人アカウント検索が再開できる。

注意: 別セッションの作業に影響する可能性があるため、許可なしに `kill` しない。

#### Codex で OAuth 認証URLが出たときの運用（重要）

Codex で Google Workspace MCP が `ACTION REQUIRED: Google Authentication Needed` と認証URLを返した場合、**URLをユーザーに貼って final で終了しない**。ユーザーは気づけないことがあるため、次の順で作業を継続する。

1. 認証URLを取得したら、Codex の commentary で「個人 Google アカウントで承認待ち」であることを短く通知する。
2. GUI 操作の承認を取り、`open '<認証URL>'` でブラウザタブを開く。みのるんには `<メールアドレス>` で許可してもらう。
3. ブラウザを開いたあとも final で終了せず、Codex 側で待機中であることを伝える。
4. 認証完了後、同じ MCP ツール呼び出しを Codex が再試行し、元の作業（Sheets 読み書き等）を最後まで続ける。
5. 認証URLが期限切れ・state不一致になった場合は、MCPツールを再実行して新しいURLを取り直し、同じ手順を繰り返す。

判断ポイント: ユーザーに必要なのは「リンクを探してクリックすること」ではなく「ブラウザ上で許可すること」。したがって、Codex は可能な限りブラウザタブを開き、ユーザーの操作待ちであることを明示する。

認証後のブラウザで `Authentication Processing Error` / `(invalid_request) client_secret is missing` が表示された場合、MCP が生成した認証URL方式では続行できない。すぐに Step 8 のスタンドアロンスクリプト方式へ切り替え、`~/.config/google-workspace-mcp/gcp-oauth.keys.json` の client secret を使って `~/.google_workspace_mcp/credentials/<メールアドレス>.json` を再保存する。スクリプト実行時もブラウザを開き、ユーザーには個人アカウントで許可してもらい、完了後に元の MCP 操作を再試行する。

#### 個人アカウントなど、特定の Chrome プロファイルで認証したい場合

> **Tip**: 認証したい個人アカウントで **すでに Chrome がログイン済み** の場合は、バックグラウンド実行＋URL手動コピペは不要。Step 8 のスクリプトをそのまま（`open_browser=True` のデフォルトで）走らせれば、Chrome が自動で開き、そのプロファイルでワンクリック許可するだけで完了する。

ブラウザの自動起動だとデフォルトプロファイル（個人用）が開いてしまう。
その場合は**バックグラウンド実行 → URLを手動で個人用 Chrome に貼る**方式を使う。

> ⚠️ **stdout バッファリング注意**：バックグラウンド実行では stdout がブロックバッファされ「Please visit this URL...」が出力ファイルに書き込まれない。**必ず `PYTHONUNBUFFERED=1` + `python -u` を併用** すること。

> 💡 **`open_browser=False` を併用するのが確実**：自動オープンを試みると意図しないプロファイルにフォーカスが奪われがち。`flow.run_local_server()` の引数を `open_browser=False` に書き換えてから走らせ、URL は自分で取り出して個人用 Chrome に貼る方が事故が少ない。

```bash
# USER_EMAIL が <メールアドレス> になっていることを確認したあと…
# （スクリプト内の run_local_server は open_browser=False に変更しておく）

# バックグラウンドで実行（PYTHONUNBUFFERED + -u で stdout を即時フラッシュ）
PYTHONUNBUFFERED=1 ~/.local/share/uv/tools/workspace-mcp/bin/python -u \
  /tmp/get_google_token.py > /tmp/google_auth_output.txt 2>&1 &

# 数秒待ってURLを取得
sleep 3
grep -o 'https://accounts.google.com[^ ]*' /tmp/google_auth_output.txt \
  | tr -d '\n' | pbcopy
echo "✅ クリップボードにOAuth URLをコピーしました"
```

`pbcopy` で **クリップボードにコピー** しておけば、個人用 Chrome プロファイルのアドレスバーに **⌘V → Enter** で貼り付けるだけで進む。改行ノイズが入る心配もない。許可 → スクリプト終了で「✅ 保存完了」が出力ファイルに書かれれば完了。

> 🔁 **同じスクリプトを再実行する際の落とし穴**：前回の認証で port 8080 が TIME_WAIT 状態になっていると `OSError: [Errno 48] Address already in use` で起動できないことがある。Step 8 のスクリプトに `socketserver.TCPServer.allow_reuse_address = True` を入れてあれば回避できる（既に上記スクリプトに反映済み）。それでも再起動できない場合は `lsof -ti :8080 | xargs kill -9` で強制解放してから再実行。

## セキュリティ注意点

| 注意点 | 対策 |
|-------|------|
| OAuth トークンが平文 JSON で保存される | `chmod 600` でアクセス制限 |
| credentials.json を Git にコミットしない | `.gitignore` に `gcp-oauth.keys.json` を追加 |
| Testing モードのトークン有効期限 | 7日ごとに再認証が必要（スタンドアロンスクリプトで再実行） |
| スコープは最小限に | 読み取りのみなら `gmail.readonly` だけ要求 |

## Gmail API スコープ一覧

| スコープ | 権限 |
|---------|------|
| `gmail.readonly` | 読み取りのみ（推奨） |
| `gmail.send` | 送信のみ |
| `gmail.compose` | 下書き作成 |
| `gmail.modify` | 読み取り + ラベル変更 |
| `https://mail.google.com/` | 全操作（最高権限） |

制限付きスコープ（readonly 含む）は Google によるセキュリティ審査が必要だが、**自分のアカウントのみに使うローカル MCP サーバーは審査不要**。
