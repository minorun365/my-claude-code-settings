---
name: kb-ec2-ssm
description: EC2 + SSM Session Manager の構築・運用ナレッジ。Claude Code on EC2、VSCode Remote-SSH、tmux永続化、CDK User Data等
user-invocable: true
model: sonnet
---

# EC2 + SSM Session Manager ナレッジ

EC2上でClaude Codeを常時稼働させる構成（claude-on-ec2）の構築・運用で得た知見。

---

## VSCode Remote-SSH（SSM 経由）の設定

### ~/.ssh/config の書き方

ProxyCommand は **必ず1行で書く**。複数行（バックスラッシュ改行）はVSCodeが `Unexpected line break` エラーを出す。

```
# NG: 複数行（VSCodeで失敗する）
Host claude-ec2
    ProxyCommand aws ssm start-session \
        --target %h \
        --document-name AWS-StartSSHSession \
        ...

# OK: 1行
Host claude-ec2
    HostName <インスタンスID>
    User ec2-user
    StrictHostKeyChecking accept-new
    ProxyCommand aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p --profile <profile> --region <region>
```

### SSH公開鍵のEC2への登録

EC2に `AWS-StartSSHSession` 経由でSSH接続する場合、EC2側の `~/.ssh/authorized_keys` にクライアント公開鍵の登録が必要。SSM send-command で行う。

```bash
# 1. 公開鍵がなければ生成
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" -C "macbook-name"

# 2. SSM send-command で EC2 の authorized_keys に登録
PUBKEY=$(cat ~/.ssh/id_ed25519.pub)
aws ssm send-command \
  --instance-id <インスタンスID> \
  --document-name "AWS-RunShellScript" \
  --parameters "commands=[\"mkdir -p /home/ec2-user/.ssh && echo '$PUBKEY' >> /home/ec2-user/.ssh/authorized_keys && chmod 600 /home/ec2-user/.ssh/authorized_keys && chown ec2-user:ec2-user /home/ec2-user/.ssh/authorized_keys\"]" \
  --profile <profile> --region <region>

# 3. 接続テスト
ssh -o BatchMode=yes <Host名> echo ok
```

### 接続エラー一覧

| エラー | 原因 | 解決策 |
|--------|------|--------|
| `Unexpected line break at aws ssm` | ProxyCommandが複数行 | 1行にまとめる |
| `Host key verification failed.` | known_hostsに未登録 | `StrictHostKeyChecking accept-new` を設定に追加 |
| `Permission denied (publickey)` | authorized_keysに公開鍵なし | SSM send-commandで公開鍵を登録 |
| `SessionManagerPlugin is not found` | プラグイン未インストール | `brew install --cask session-manager-plugin` |

---

## tmux によるプロセス永続化と自動再起動

### remain-on-exit + respawn-pane

claudeなどのプロセスが終了しても自動で再起動する仕組み：

```bash
tmux new-session -d -s <セッション名> -x 220 -y 50
tmux set-option -t <セッション名> remain-on-exit on
tmux set-hook -t <セッション名> pane-died "respawn-pane -k -t <セッション名>"
tmux send-keys -t <セッション名> "cd ~ && <起動コマンド>" Enter
```

| 設定 | 効果 |
|------|------|
| `remain-on-exit on` | プロセス終了後もペインを残す（dead状態） |
| `pane-died` フック | ペインがdead状態になったときに発火 |
| `respawn-pane -k` | deadペインを強制的に再起動 |

---

## CDK User Data の落とし穴

### heredocでの ! (感嘆符) エスケープ問題

TypeScript配列を `.join('\n')` で結合してheredocを生成すると、シェバン行 `#!/bin/bash` が `#\!/bin/bash` に文字化けすることがある。

**確認方法**:
```bash
xxd /usr/local/bin/スクリプト名.sh | head -1
# 2321 が正常（#!/）、235c21 が文字化け（#\!）
```

**結果**: systemd が `Exec format error` (status=203) でスクリプトを実行できない。

**対処**: EC2上で直接 `cat > /path/to/script.sh << 'EOF' ... EOF` で書き直す。

### User Dataはデフォルトで初回起動時のみ実行

CDKでUser Dataを更新して `cdk deploy` しても EC2 が**停止→起動**されるだけで再実行されない。
変更を反映させるには `cloud-init clean` で強制再実行が必要。

```bash
sudo cloud-init clean --logs
sudo cloud-init init
sudo cloud-init modules --mode config
sudo cloud-init modules --mode final
```

---

## Claude Code on EC2 の設定

### Workspace not trusted エラー

```
Error: Workspace not trusted. Please run `claude` in / first...
```

`/`（ルート）など信頼されていないディレクトリで `claude` や `claude remote-control` を起動すると発生。
起動スクリプトに `cd /home/ec2-user &&` を先頭に追加して回避する。

### /config で Remote Control を全セッション自動有効化

Claude Code プロンプトで `/config` を実行し、「すべてのセッションでリモートコントロールを有効にする」を `true` に設定。
以降は `claude` を起動するだけで自動的に Remote Control が有効になる。

### systemd + tmux の自動起動構成

```
/etc/systemd/system/claude-code.service
  ↓ EC2起動時に実行
/usr/local/bin/claude-autostart.sh
  ↓ tmuxセッション「claude」を作成（remain-on-exit設定込み）
  ↓ tmux内で claude を起動
Remote Control が自動有効化（/config 設定済みの場合）
  ↓
スマホ・ブラウザから claude.ai/code で接続可能
```

### tmuxのネスト接続エラー

SSMセッション内でさらに `tmux attach` しようとすると：
```
sessions should be nested with care, unset $TMUX to force
```
これはすでにtmux内にいることを示す正常なメッセージ。`Ctrl+B, D` でデタッチすれば OK。

### ターミナルからの接続手順

EC2上のClaude Codeに接続するときの手順：

#### Step 1: SSOセッション確認（Bashで実行）

`aws sts get-caller-identity --profile sandbox` を実行する。
- 成功したら「✅ SSOセッション有効」と表示してStep 2に進む
- 失敗したら「⚠️ SSOセッション切れ。次のコマンドを実行してください：`aws sso login --profile sandbox`」と表示して終了する

#### Step 2: 接続コマンドを表示（Bashで実行しない）

SSMセッションはインタラクティブなため、Bashツールでは実行できない。
代わりに以下をそのままコピペしやすい形で出力する：

```
# ターミナルで実行してください

aws ssm start-session --target i-02493e718117e1af0 --profile sandbox --region us-east-1
# 接続後↓
sudo su - ec2-user
# → 自動で tmux にアタッチされて Claude Code が使えます
```

最後に一言添える：「Mac を閉じても tmux がデタッチされるだけでセッションは継続します。スマホの Claude アプリからそのまま続きができます。」

---

## EC2 上での GitHub 認証（`gh auth login`）

### `read:org` スコープ不足エラー

EC2 上で `gh auth login` に PAT を貼り付けると以下のエラーが出ることがある：

```
error validating token: missing required scope 'read:org'
```

**原因**: PAT に `read:org` スコープが付与されていない。

**必要なスコープ（Classic PAT）**:
- ✅ `repo`
- ✅ `read:org`
- ✅ `gist`
- ✅ `workflow`

**対処手順**:
1. https://github.com/settings/tokens で既存トークンを **Delete**（スコープ変更ではなく再発行が確実）
2. **Generate new token (classic)** で上記4スコープにチェックして生成
3. 1Password `Private/GitHub PAT` を新しいトークンで更新
4. EC2 で `gh auth login` を再実行してトークンを貼り付け

> スコープを変更しても既存のトークン文字列は変わらないため、Regenerate または Delete → 新規発行を行うこと。

---

## 古いtmuxソケット残骸の問題

`/tmp/tmux-<uid>/` にソケットファイルが残骸として残っているがサーバーは起動していない状態だと、`tmux has-session` がエラーを返して自動起動スクリプトが誤動作することがある。

```bash
# スクリプト冒頭でクリーンアップ
tmux kill-server 2>/dev/null || true
sleep 0.5
```
