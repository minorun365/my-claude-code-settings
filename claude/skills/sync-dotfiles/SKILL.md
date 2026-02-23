---
name: sync-dotfiles
description: dotfiles（Zsh・Git・Ghostty設定）をGitHubリポジトリとローカル間で双方向同期する。新しい方を自動判定して取り込む
user-invocable: true
---

# dotfiles 同期

dotfilesリポジトリ（GitHub）とローカルのZsh・Git・Ghostty設定ファイルを双方向同期します。
各ファイルについて**新しい方を自動判定**し、取り込みます。

## リポジトリパス

```
~/git/minorun365/dotfiles/
```

## 同期対象ファイル

| リポジトリ | ローカル | 種別 |
|-----------|---------|------|
| `zshrc` | `~/.zshrc` | Zsh |
| `zshenv` | `~/.zshenv` | Zsh |
| `zprofile` | `~/.zprofile` | Zsh |
| `gitconfig` | `~/.gitconfig` | Git |
| `gitconfig-personal` | `~/.gitconfig-personal` | Git |
| `ghostty/config` | `~/.config/ghostty/config` | Ghostty |

## 実行手順

### Step 1: リポジトリを最新化

```bash
cd ~/git/minorun365/dotfiles && git pull
```

### Step 2: シンボリックリンク状態を確認

各ファイルについて、ローカルがシンボリックリンクか通常ファイルかを確認する。

```bash
# Zsh・Git設定（~/.<ファイル名> パターン）
for f in zshrc zshenv zprofile gitconfig gitconfig-personal; do
  target="$HOME/.$f"
  if [ -L "$target" ]; then
    echo "✅ $target → $(readlink "$target") (symlink)"
  elif [ -f "$target" ]; then
    echo "⚠️  $target は通常ファイル（symlinkではない）"
  else
    echo "❌ $target が存在しない"
  fi
done

# Ghostty設定（パスが異なる）
GHOSTTY_TARGET="$HOME/.config/ghostty/config"
if [ -L "$GHOSTTY_TARGET" ]; then
  echo "✅ $GHOSTTY_TARGET → $(readlink "$GHOSTTY_TARGET") (symlink)"
elif [ -f "$GHOSTTY_TARGET" ]; then
  echo "⚠️  $GHOSTTY_TARGET は通常ファイル（symlinkではない）"
else
  echo "❌ $GHOSTTY_TARGET が存在しない"
fi
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

# Zsh・Git設定（~/.<ファイル名> パターン）
for f in zshrc zshenv zprofile gitconfig gitconfig-personal; do
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

# Ghostty設定（パスが異なる）
GHOSTTY_REPO="$DOTFILES_DIR/ghostty/config"
GHOSTTY_LOCAL="$HOME/.config/ghostty/config"

if [ ! -f "$GHOSTTY_LOCAL" ]; then
  echo "📥 ghostty/config: ローカルに存在しない → リポジトリからコピー"
elif diff -q "$GHOSTTY_REPO" "$GHOSTTY_LOCAL" > /dev/null 2>&1; then
  echo "✅ ghostty/config: 内容が同一"
else
  repo_time=$(stat -f %m "$GHOSTTY_REPO" 2>/dev/null || stat -c %Y "$GHOSTTY_REPO")
  local_time=$(stat -f %m "$GHOSTTY_LOCAL" 2>/dev/null || stat -c %Y "$GHOSTTY_LOCAL")
  if [ "$local_time" -gt "$repo_time" ]; then
    echo "📤 ghostty/config: ローカルが新しい → リポジトリに反映"
  else
    echo "📥 ghostty/config: リポジトリが新しい → ローカルに反映"
  fi
fi
```

**判定結果をユーザーに提示し、確認を取ってから以下を実行する：**

- **ローカルが新しい場合**: ローカルの内容をリポジトリにコピー
  ```bash
  # Zsh・Git設定の場合
  cp ~/.$f ~/git/minorun365/dotfiles/$f
  # Ghostty設定の場合
  cp ~/.config/ghostty/config ~/git/minorun365/dotfiles/ghostty/config
  ```

- **リポジトリが新しい場合**: ローカルをバックアップしてリポジトリの内容で上書き
  ```bash
  # Zsh・Git設定の場合
  cp ~/.$f ~/.$f.backup.$(date +%Y%m%d)
  cp ~/git/minorun365/dotfiles/$f ~/.$f
  # Ghostty設定の場合
  cp ~/.config/ghostty/config ~/.config/ghostty/config.backup.$(date +%Y%m%d)
  cp ~/git/minorun365/dotfiles/ghostty/config ~/.config/ghostty/config
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

### Step 5: Claude Code設定も同期するか確認

ユーザーに以下を確認する：

> Claude Code設定（skills、CLAUDE.md、mcpServers等）も同期しますか？

- **Yesの場合**: `/sync-claude-code-settings` スキルの手順に従って実行する
- **Noの場合**: 同期完了

## 注意事項

- **必ずユーザーに確認を取ってから**ファイルの上書きやコミット・プッシュを行う
- 通常ファイルを上書きする前に必ずバックアップを作成する
- `diff` で差分内容をユーザーに見せて、意図しない変更がないか確認する
- `install.sh` は既存の通常ファイルをタイムスタンプ付きでバックアップしてからシンボリックリンクを作成する
