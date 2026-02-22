---
name: sync-dotfiles
description: dotfiles（Zsh設定）をGitHubリポジトリとローカル間で双方向同期する。新しい方を自動判定して取り込む
user-invocable: true
---

# dotfiles 同期

dotfilesリポジトリ（GitHub）とローカルの `~/` のZsh設定ファイルを双方向同期します。
各ファイルについて**新しい方を自動判定**し、取り込みます。

## リポジトリパス

```
~/git/minorun365/dotfiles/
```

## 同期対象ファイル

| リポジトリ | ローカル |
|-----------|---------|
| `zshrc` | `~/.zshrc` |
| `zshenv` | `~/.zshenv` |
| `zprofile` | `~/.zprofile` |

## 実行手順

### Step 1: リポジトリを最新化

```bash
cd ~/git/minorun365/dotfiles && git pull
```

### Step 2: シンボリックリンク状態を確認

各ファイルについて、ローカルがシンボリックリンクか通常ファイルかを確認する。

```bash
for f in zshrc zshenv zprofile; do
  target="$HOME/.$f"
  if [ -L "$target" ]; then
    echo "✅ $target → $(readlink "$target") (symlink)"
  elif [ -f "$target" ]; then
    echo "⚠️  $target は通常ファイル（symlinkではない）"
  else
    echo "❌ $target が存在しない"
  fi
done
```

### Step 3: 状態に応じた同期

#### パターンA: シンボリックリンクが正常な場合

シンボリックリンクが `~/git/minorun365/dotfiles/` を指している場合、`git pull` で既にローカルも最新化されている。

- ローカルで編集した変更がある場合 → Step 4 でコミット＆プッシュ
- 何も変更がない場合 → 同期完了

#### パターンB: 通常ファイルが存在する場合（symlinkが壊れている）

各ファイルについて内容を比較し、新しい方を採用する。

```bash
DOTFILES_DIR="$HOME/git/minorun365/dotfiles"
for f in zshrc zshenv zprofile; do
  repo="$DOTFILES_DIR/$f"
  local="$HOME/.$f"

  if [ ! -f "$local" ]; then
    echo "📥 $f: ローカルに存在しない → リポジトリからコピー"
    continue
  fi

  if diff -q "$repo" "$local" > /dev/null 2>&1; then
    echo "✅ $f: 内容が同一"
    continue
  fi

  # 内容が異なる場合、タイムスタンプで比較
  repo_time=$(stat -f %m "$repo" 2>/dev/null || stat -c %Y "$repo")
  local_time=$(stat -f %m "$local" 2>/dev/null || stat -c %Y "$local")

  if [ "$local_time" -gt "$repo_time" ]; then
    echo "📤 $f: ローカルが新しい → リポジトリに反映"
  else
    echo "📥 $f: リポジトリが新しい → ローカルに反映"
  fi
done
```

**判定結果をユーザーに提示し、確認を取ってから以下を実行する：**

- **ローカルが新しい場合**: ローカルの内容をリポジトリにコピー
  ```bash
  cp ~/.$f ~/git/minorun365/dotfiles/$f
  ```

- **リポジトリが新しい場合**: ローカルをバックアップしてリポジトリの内容で上書き
  ```bash
  cp ~/.$f ~/.$f.backup.$(date +%Y%m%d)
  cp ~/git/minorun365/dotfiles/$f ~/.$f
  ```

- **同期後、シンボリックリンクの再設定を提案する**
  ```bash
  cd ~/git/minorun365/dotfiles && ./install.sh
  ```

#### パターンC: ローカルにファイルが存在しない場合

`install.sh` を実行してシンボリックリンクを作成する。

```bash
cd ~/git/minorun365/dotfiles && ./install.sh
```

### Step 4: ローカル変更をリポジトリにプッシュ

ローカルで変更があった場合（パターンA で編集済み、またはパターンB でローカルが新しかった場合）：

```bash
cd ~/git/minorun365/dotfiles
git status
git diff
```

差分をユーザーに提示し、確認後にコミット＆プッシュ。

```bash
git add -A
git commit -m "dotfiles同期"
git push
```

## 注意事項

- **必ずユーザーに確認を取ってから**ファイルの上書きやコミット・プッシュを行う
- 通常ファイルを上書きする前に必ずバックアップを作成する
- `diff` で差分内容をユーザーに見せて、意図しない変更がないか確認する
- `install.sh` は既存の通常ファイルをタイムスタンプ付きでバックアップしてからシンボリックリンクを作成する
