# npm パッケージ公開（CLIツール）

## npm パッケージ公開（CLI ツール）

### 2FA 制約：publish 時はパスキー不可

npm にパスキーを設定していても、`npm publish` 時の 2FA にはパスキーは使えない（ログインのみ有効）。`--auth-type=web` を付けても publish 時の 2FA には効果なし。

publish 時に 2FA を回避するには：
- OTP コード（認証アプリ/メール）+ `npm publish --otp=<6桁>`
- または **Bypass 2FA 付き Granular Access Token** を `~/.npmrc` に設定

### Granular Access Token の罠（unscoped パッケージ）

| Packages 選択 | 動作 |
|------|------|
| `Only select packages and scopes` → `@minorun365` を選択 | **organization scope 専用**（`@org/pkg` 形式のみ）。unscoped な `minorun365` への publish 不可 |
| `All packages` | unscoped + scoped 両方に対応。新規パッケージの初回 publish も可能 |

**unscoped パッケージ（`@` なし）の初回 publish には「All packages」が必須**。誤った場合のエラー:

```
403 Forbidden - You may not perform that action with these credentials.
```

### 推奨トークン設定（Bypass 2FA フロー）

```
Token name:  <任意>
Bypass 2FA:  ✅ ON
Permissions: Read and write
Packages:    All packages
Expiration:  90日（最大）
```

### 永続運用パターン（1Password + ~/.npmrc）

毎回トークンを発行・revoke するのは手間なので、**90日トークンを1回発行 → 1Password 保存 + ~/.npmrc 永続設定** の運用が楽：

```bash
# 1. ~/.npmrc に永続設定（このMacで publish 自動化）
npm config set //registry.npmjs.org/:_authToken=<token>

# 2. 1Password Private Vault に保存（バックアップ + 他Mac共有）
op item create --category="API Credential" --title="npm" --vault="Private" \
  --account=my.1password.com \
  username="__token__" \
  credential="<token>" \
  notesPlain="npm publish 用 Granular Access Token. 90日有効. <失効日>" \
  --tags="npm,publish"

# 3. 動作確認
npm whoami
```

### 他Macで同じトークンを使う

```bash
TOKEN=$(op read "op://Private/npm/credential")
npm config set //registry.npmjs.org/:_authToken=$TOKEN
```

### 90日後の失効対応

1. ブラウザで新トークン発行（前回手順）
2. `op item edit "npm" credential="<新トークン>"` で 1Password 更新
3. `npm config set //registry.npmjs.org/:_authToken=<新トークン>` で `~/.npmrc` 更新
4. 古いトークンは npm 側で自動失効するが、念のため revoke も推奨

### モノレポで data.json を Python/JS 両方に同梱する

ルートに `data.json` を SSOT として配置し、各言語でパッケージ同梱する場合：

**Python（PyPI）**:
- `python/src/<pkg>/data.json` に**実体コピー**を置く（`.gitignore` で除外）
- ビルド前に手動でコピー: `cp ../../data.json python/src/<pkg>/data.json`
- **シンボリックリンクは NG**：`python -m build` の sdist→wheel 変換時に宙ぶらりんになる

**Node.js（npm）**:
- `prepack` フックでコピー（`prepublishOnly` ではなく `prepack` を使う）
- `prepublishOnly` は `npm pack` で走らないため、`npm pack --dry-run` で `data.json` が含まれない問題が起きる

```json
{
  "scripts": {
    "prepack": "cp ../data.json data.json"
  },
  "files": ["src/", "data.json"]
}
```
