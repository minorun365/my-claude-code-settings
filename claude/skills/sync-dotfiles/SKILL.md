---
name: sync-dotfiles
description: dotfiles（Zsh・Git設定）をGitHubリポジトリとローカル間で双方向同期する。新しい方を自動判定して取り込む
user-invocable: true
model: sonnet
---

# dotfiles 同期

dotfilesリポジトリ（GitHub）とローカルのZsh・Git設定ファイルを双方向同期します。
各ファイルについて**新しい方を自動判定**し、取り込みます。

## リポジトリパス

```
~/git/dotfiles/
```

## 同期対象ファイル

| リポジトリ | ローカル | 種別 |
|-----------|---------|------|
| `zshrc` | `~/.zshrc` | Zsh |
| `zshenv` | `~/.zshenv` | Zsh |
| `zprofile` | `~/.zprofile` | Zsh |
| `gitconfig` | `~/.gitconfig` | Git |
| `gitconfig-personal` | `~/.gitconfig-personal` | Git |

## 実行手順

### Step 1: リポジトリを最新化

```bash
cd ~/git/dotfiles && git pull
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
```

### Step 3: 状態に応じた同期

#### パターンA: シンボリックリンクが正常な場合

シンボリックリンクが `~/git/dotfiles/` を指している場合、`git pull` で既にローカルも最新化されている。

- ローカルで編集した変更がある場合 → Step 4 でコミット＆プッシュ
- 何も変更がない場合 → 同期完了

#### パターンB: 通常ファイルが存在する場合（symlinkが壊れている）

各ファイルについて内容を比較し、新しい方を採用する。

```bash
DOTFILES_DIR="$HOME/git/dotfiles"

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
```

**判定結果をユーザーに提示し、確認を取ってから以下を実行する：**

- **ローカルが新しい場合**: ローカルの内容をリポジトリにコピー
  ```bash
  cp ~/.$f ~/git/dotfiles/$f
  ```

- **リポジトリが新しい場合**: ローカルをバックアップしてリポジトリの内容で上書き
  ```bash
  cp ~/.$f ~/.$f.backup.$(date +%Y%m%d)
  cp ~/git/dotfiles/$f ~/.$f
  ```

- **同期後、シンボリックリンクの再設定を提案する**
  ```bash
  cd ~/git/dotfiles && ./install.sh
  ```

#### パターンC: ローカルにファイルが存在しない場合

`install.sh` を実行してシンボリックリンクを作成する。

```bash
cd ~/git/dotfiles && ./install.sh
```

### Step 4: ローカル変更をリポジトリにプッシュ

ローカルで変更があった場合（パターンA で編集済み、またはパターンB でローカルが新しかった場合）：

差分確認なしで自動コミット＆プッシュする（同期による変更は想定内のため）。

> ⚠️ **`git add -A` は絶対に使わない**。`~/git/dotfiles/` を含むリポジトリで、`dotfiles/` はその中のサブディレクトリ（兄弟に `docs/` `notes/` `marp/` `qiita/` 等がある）。`git add -A` は**リポジトリ全体**を対象にするため、`dotfiles/` 外の未コミット変更まで巻き込む（過去にこの事故が発生）。`cd` 済みなので `git add -- .`（＝カレント `dotfiles/` 以下のみ）を使うこと。

```bash
cd ~/git/dotfiles
git add -- .            # dotfiles/ 配下のみ。git add -A は禁止（モノレポの兄弟ディレクトリを巻き込む）
git commit -m "dotfiles同期"
git push
```

### Step 5: Claude Code / Codex 設定も同期するか確認

ユーザーに以下を確認する：

> Claude Code設定（skills、CLAUDE.md、mcpServers等）も同期しますか？

- **Yesの場合**: `/sync-claude-code-settings` スキルの手順に従って実行する
- **Noの場合**: 次を確認する

> Codex設定（AGENTS.md、config.toml、agents、skills）も同期しますか？

- **Yesの場合**: `/sync-codex-settings` スキルの手順に従って実行する
- **Noの場合**: 同期完了

## 注意事項

- **ファイルの上書き**（パターンBでローカルが新しい/古い場合）はユーザーに確認を取ってから行う
- 通常ファイルを上書きする前に必ずバックアップを作成する
- **コミット・プッシュは自動実行**する（同期による変更は想定内のため、ユーザー確認は不要）
- `install.sh` は既存の通常ファイルをタイムスタンプ付きでバックアップしてからシンボリックリンクを作成する
