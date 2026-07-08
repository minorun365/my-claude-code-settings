# GitHub, gh CLI, and OSS contribution

## 目次

- GitHub Enterprise (GHE) HTTPS push: 403 の根本診断と修正
  - 症状
  - よくある原因と優先度
  - 診断フロー
  - 修正方法
  - なぜ「トークン付き URL」ワークアラウンドが効いていたか
- gh CLI: 同一 host に複数アカウント並存（multi-account）
  - セットアップ
  - 状態確認
  - アクティブ切替
  - Org アクセス権限はアカウント単位
  - Bash ツールから対話的認証する際の罠
- OSS コントリビューション（Python SDK へのPR）
  - ワークフロー全体像
  - Strands Agents Python SDK の具体例
  - Python SDK 特有の注意点
  - トラブルシューティング

## GitHub Enterprise (GHE) HTTPS push: 403 の根本診断と修正

### 症状

`git push` で `remote: Write access to repository not granted. HTTP 403` が出る。
`gh auth status` は正常、`gh api repos/...` も成功するのに git 操作だけ 403。

### よくある原因と優先度

| 優先度 | 原因 | 確認方法 |
|--------|------|---------|
| 🔴 高 | `~/.netrc` に古いトークンが残っている | `cat ~/.netrc` |
| 🟡 中 | macOS キーチェーンに古いトークンが残っている | `security find-internet-password -s <ghe-host> -w` |
| 🟡 中 | `gh auth login` で OAuth トークン (`gho_*`) が使われており GHE server が write を拒否 | `GH_HOST=<ghe-host> gh auth status` で Token の先頭確認 |

### 診断フロー

```bash
# 1. credential helper が何を返すか確認（PAT が返るはず）
printf "protocol=https\nhost=<ghe-host>\n" | git credential fill

# 2. curl で PAT 単体テスト（200 なら PAT 自体は有効）
curl -s -o /dev/null -w "%{http_code}" \
  -u "<sub-account>:$(GH_HOST=<ghe-host> gh auth token)" \
  "https://<ghe-host>/<sub-account>/<repo>.git/info/refs?service=git-upload-pack"

# 3. .netrc を確認（← これが原因のことが多い！）
cat ~/.netrc

# 4. キーチェーンを確認
security find-internet-password -s <ghe-host> -w 2>&1
```

### 修正方法

**ケース1: `.netrc` に古いトークンがある場合（最多）**

```bash
# バックアップしてから削除
mv ~/.netrc ~/.netrc.bak
```

Git は credential helper より**先に `.netrc` を参照する**ため、ここに古いトークンがあると credential helper は呼ばれない。

**ケース2: キーチェーンに古いトークンがある場合**

```bash
security delete-internet-password -s <ghe-host>
```

**ケース3: OAuth トークン (`gho_*`) で write 不可の場合**

GHE server 管理者が gh CLI OAuth App の write 権限を制限しているケース。
PAT (`ghp_*`) に切り替える：

```bash
# GHE で PAT 作成後（Scopes: repo, read:org, gist, workflow）
GH_HOST=<ghe-host> gh auth login --hostname <ghe-host> --with-token <<< "<PAT>"
```

### なぜ「トークン付き URL」ワークアラウンドが効いていたか

```bash
# これは動く（でも根本解決ではない）
git remote set-url origin "https://<sub-account>:$(GH_HOST=<ghe-host> gh auth token)@<ghe-host>/..."
```

URL に埋め込んだ場合、`.netrc` や credential helper を**バイパス**して直接そのトークンを使う。`.netrc` の古いトークン問題が隠蔽されていただけ。

---

## gh CLI: 同一 host に複数アカウント並存（multi-account）

`gh` 2.40+ では **同じ host に複数アカウントを並存**して保持できる。1台の Mac で複数の GitHub アカウントを使い分けるときに便利。

### セットアップ

```bash
# 既に minorun365 でログイン済みの状態で、追加アカウントをログイン
gh auth login --hostname github.com --git-protocol https --web --scopes "repo,read:org"
# → 既存アカウントには影響せず、追加でサブアカウントが入る
```

### 状態確認

```bash
gh auth status
# github.com
#   ✓ Logged in to github.com account <sub-account> (keyring)   ← Active: true
#     - Active account: true
#   ✓ Logged in to github.com account minorun365 (keyring)
#     - Active account: false
```

### アクティブ切替

```bash
gh auth switch -h github.com -u minorun365
# → minorun365 がアクティブに
```

### Org アクセス権限はアカウント単位

```bash
# minorun365 アクティブ → <org名> org が見えない（権限なし）
gh api orgs/<org名>/repos --paginate
# → []

# <sub-account> アクティブ → <org名> のリポ一覧取得成功
gh auth switch -h github.com -u <sub-account>
gh api orgs/<org名>/repos --paginate
# → [{ "name": "arch-samples", ... }]
```

### Bash ツールから対話的認証する際の罠

`gh auth login --web` 実行時、Claude Code の Bash ツールは **permission UI が VS Code 拡張サイドパネル下部に出る**。Allow を押さないとコマンドは起動すらしない（「rejected」が即返る）。ユーザーが「ブラウザが開かない」と訴える時は、permission プロンプトが見えていない可能性大。

回避策：
- どうしても Bash ツール経由で動かない場合は、**別ターミナルでユーザーに手動実行**してもらう
- `gh auth login --hostname github.com --git-protocol https --web --scopes "repo,read:org"` を提示

---

## OSS コントリビューション（Python SDK へのPR）

### ワークフロー全体像

1. **Issue 確認** → 既存 Issue/PR の重複チェック
2. **CONTRIBUTING.md 確認** → 開発環境・テスト・スタイルガイドを把握
3. **過去の類似 PR を調査** → `gh pr list --state merged --search "関連キーワード"`
4. **ブランチ作成** → `git switch -c <type>/<description>`
5. **実装 + テスト** → `hatch test`, `hatch fmt --formatter/--linter`
6. **実機検証** → `pip install -e .` でローカル変更を反映し、実際のAPIで動作確認
7. **コミット** → Conventional Commits 準拠（`feat:`, `chore:`, `fix:`）
8. **PR 作成** → `gh pr create` with 詳細な説明文

### Strands Agents Python SDK の具体例

**開発環境セットアップ:**
```bash
# hatch インストール
pip install hatch

# pre-commit hooks 設定
pre-commit install -t pre-commit -t commit-msg

# 開発シェル起動（推奨）
hatch shell
```

**テスト実行:**
```bash
# フォーマッタ
hatch fmt --formatter

# リンター（ruff + mypy）
hatch fmt --linter

# ユニットテスト
hatch test

# カバレッジ付き
hatch test -c

# 統合テスト（AWS認証が必要）
hatch run test-integ

# 特定ファイルのみ
hatch test tests/strands/models/test_bedrock.py

# 特定テスト関数のみ
pytest tests/strands/models/test_bedrock.py::test_function_name -vv
```

**ローカル変更の反映:**
```bash
# editable install（コード変更が即座に反映される）
pip install -e .

# 動作確認用スクリプト
python -c "
from strands import Agent
agent = Agent()
print(agent.model.config)
result = agent('hello')
print(result)
"
```

**コミットメッセージ:**
- **Conventional Commits** 必須（pre-commit hook で強制）
- タイプ: `feat`, `fix`, `chore`, `docs`, `ci`, `test`, `refactor`
- スコープ: `(bedrock)`, `(agent)`, `(mcp)` 等
- Breaking change は本文に `BREAKING CHANGE:` を含める

```bash
# 例: heredoc でコミットメッセージを作成
git commit -m "chore(bedrock): update default model to Claude Sonnet 4.6

BREAKING CHANGE: The default Bedrock model has been updated.
Users must enable Claude Sonnet 4.6 in Bedrock model access settings.

Closes #2130"
```

**PR Description ガイドライン (`docs/PR.md`):**
- **Motivation（WHY）** — なぜこの変更が必要か
- **Public API Changes** — before/after コードスニペット
- **Use Cases（任意）** — 非自明な機能のみ
- **Breaking Changes** — 何が壊れるか、マイグレーション方法
- **実装詳細は書かない** — コミットメッセージと diff で十分

**PR 作成:**
```bash
gh pr create \
  --repo strands-agents/sdk-python \
  --head <your-fork>:<branch> \
  --base main \
  --title "<type>(<scope>): <description>" \
  --body "PR 本文をファイルから読み込むか heredoc で指定"
```

### Python SDK 特有の注意点

1. **Import の整理**: 使わない import は削除（mypy が検出）
2. **テストファイルの命名**: `test_*.py` または `*_test.py`
3. **Logging スタイル**: `logger.debug("field=<%s> | message", field)` （f-string 禁止）
4. **型ヒント**: Python 3.10 ベース、mypy strict mode
5. **行長**: 120 文字（ruff 設定）
6. **非関連ファイルの revert**: フォーマッタが触った無関係なファイルは `git checkout` で戻す
7. **テスト内の固定モデルID**: ユーザーが明示指定するシナリオのテストは旧モデルIDのままでOK

### トラブルシューティング

**`hatch` が見つからない:**
```bash
pip install hatch
```

**`ValueError: unsupported hash type blake2b`:**
- pyenv + Python 3.13 で OpenSSL の問題。無害なので無視してOK

**テストが落ちる:**
```bash
# フォーマッタを先に実行
hatch fmt --formatter

# import や型エラーは linter で検出
hatch fmt --linter
```

**実機テストで古いコードが動く:**
```bash
# editable install を再実行
pip install -e .
```
