---
name: kb-1password-cli
description: 1Password CLI（op コマンド）のナレッジ。.env.op テンプレートから .env 生成、op-sync、Touch ID最小化、Vault構成、アカウント切替等
user-invocable: true
model: sonnet
---

# 1Password CLI（op）のナレッジ

## 1Password CLI (`op`) の操作ナレッジ

### 環境確認

```bash
op --version          # バージョン確認（v2.33.1 で動作確認済み）
op account list       # 登録済みアカウント一覧
op vault list --account my.1password.com   # Vault一覧（アカウント指定が必須）
```

### 複数アカウント環境

複数の 1Password アカウント（例: `my.1password.com` と組織アカウント）が登録されている場合、すべての `op` コマンドに `--account` フラグが必要。

**⚠️ よくあるハマり: `--vault Private` だけでは個人Vaultに入らない**

複数アカウント環境では `--vault Private` を指定しても、**`--account` を省略すると別アカウント側の Vault にフォールバック**することがある。エラーにならず黙って別のVaultに保存されるため気づきにくい。

```bash
# ❌ NG: --account なし → 意図しないアカウントの Vault に入る
op item create --category "API Credential" --title "Example" --vault Private

# ✅ OK: 必ず --account を明示する
op item create --category "API Credential" --title "Example" --vault Private --account my.1password.com
```

個人Vaultへの保存は **必ず `--account my.1password.com`** をセットで指定すること。

### Touch ID 認証を最小化する方法

`op` コマンドを `&&` でチェーンすると、同一シェルセッション内でキャッシュが効き Touch ID は最初の1回だけで済む。複数アイテムを登録する際は必ずまとめて実行する。

```bash
op item create ... && op item create ... && op item create ...
```

### アイテム作成

```bash
# Secure Note
op item create --category "Secure Note" --title "タイトル" --vault Private --account my.1password.com -- \
  "フィールド名1=値1" "フィールド名2=値2"

# Credit Card
op item create --category "Credit Card" --title "カード名" --vault Private --account my.1password.com -- \
  "number=カード番号" "expiry date=2030/04" "CVV=123"

# 既存アイテムを更新
op item edit "アイテム名" --vault Private --account my.1password.com "新フィールド=値"
```

### Credit Card カテゴリの制約（v2.33.1時点）

- `type` フィールド（visa/mc/amex等）は CLI では**設定不可**。エラー: `"type" field isn't supported yet`
- 有効期限は **`YYYY/MM` 形式**が必須（`MM/YY` ではエラー: `values for field type monthYear must be in YYYYMM or YYYY/MM format`）

### `.env.op` テンプレート設計時の落とし穴（op inject の罠）

`op inject` は **コメント行（`#` 始まり）であっても、行内に存在する参照リテラルを解決しようとする**。たとえば以下のような「将来用の雛形」をコメントアウトして残すとエラーになる：

```
# UPSTASH_REDIS_REST_URL=op://Private/Mastra Book Verify - Upstash Redis/rest_url
```

→ `could not find item Mastra Book Verify - Upstash Redis in vault` で `op-sync` 失敗。

さらに、コメント文中に **「op:」と「//」を組み合わせた文字列を書くだけでも** `invalid secret reference` エラーで失敗する：

```
# 説明: ここにVault/Item/Field形式で参照を追加
```
↑ これは OK。一方、↓ はエラー：
```
# 説明: ここにop://Vault/Item/Field形式で参照を追加
```
→ `invalid secret reference 'op://Vault/': too few '/'`

**対処方針**:
1. 将来用の雛形は `.env.op` に書かない。実際にアイテムを作成するタイミングで初めて追記する
2. コメントで使い方を説明したい場合は、参照リテラル風の文字列を一切使わず日本語で書く（例：「Vault名/アイテム名/フィールド名 形式」）
3. 実例を示したいときは AgentCore本など既存運用中のテンプレートファイルを参照誘導する

### アイテム検索・取得

```bash
# タイトルや名前で検索
op item list --vault Private --account my.1password.com --format json | python3 -c "
import json,sys; items=json.load(sys.stdin)
for i in items:
    if 'キーワード' in i['title']: print(i['title'], i['id'])"

# アイテム取得（フルIDかタイトルで指定）
op item get "アイテム名" --vault Private --account my.1password.com --reveal
op item get <full-uuid> --vault Private --account my.1password.com --reveal

# ⚠️ ID の先頭8文字だけでは item get できない（フルUUID or タイトルが必要）
# ⚠️ op item list に --limit フラグは存在しない（全件返却される）
```

---

## GitHub MCP PAT の管理（1Password連携）

- GitHub MCP サーバー（`@modelcontextprotocol/server-github`）の PAT は **1Password で管理**
  - アイテム: `Private/GitHub PAT`、フィールドID: `credential`（GUI表示名は「認証情報」）
  - 参照パス: `op://Private/GitHub PAT/credential`
- **PAT が切れたとき**:
  1. GitHub で新 PAT を発行（スコープ: `repo`, `read:org`, `gist`, `workflow`）
  2. 1Password「GitHub PAT」→「認証情報」フィールドを更新
  3. `/sync-claude-code-settings` → Pull → ステップ 5-3 が `op read` で自動注入
- **`op read` は日本語ラベルではなくフィールドIDで参照する**（`op://Vault/Item/fieldID`）
  - フィールドID確認: `op item get "アイテム名" --format json | jq '.fields[] | {id, label}'`
