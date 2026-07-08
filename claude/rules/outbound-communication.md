# 外部発信時の事前確認ルール

**他者の共有スペースへの発信操作**は、Bash が自動許可されていても、必ずみのるんに「こういう内容で投稿しますけど大丈夫ですか？」と**事前確認を取ってから実行**する。

技術的に hook や deny で塞いでいないので、**Claude（自分）の判断**で確実に守る。

## 対象操作（事前確認が必須）

### GitHub
**自分（minorun365）がオーナーではないリポジトリ**への発信全般：
- PR の作成 / マージ / close / reopen / convert（`gh pr create` で base が他人リポになる fork からの PR も含む）
- Issue の作成 / close / reopen / delete / transfer
- PR / Issue / Discussion へのコメント投稿（`gh pr comment`、`gh issue comment`、`gh api .../comments -X POST` 等）
- PR description の編集（`gh pr edit --body`）
- レビュー提出（`gh pr review`）
- リアクション追加（`gh api .../reactions -X POST`）

### Slack（他人がいるチャンネル全般）
- メッセージ送信、Canvas 作成・更新

### Notion（共有ワークスペース）
- 共有ページの作成・更新・コメント

### メール
- Gmail 送信

### その他 SaaS / 外部発信
- HubSpot / Atlassian / Miro 等への書き込み
- 外部 Webhook 呼び出し
- Twitter/X、Mastodon 等への投稿

### 複合コマンドも対象

`cd /tmp && gh pr comment ...` や `git status; gh issue create ...` のように、別コマンドと `&&` / `;` / `|` で連結されていても、**発信系コマンドが文字列のどこかに含まれていれば対象**。先頭コマンドが安全なものでも油断しない。

## 確認時に提示する情報

実行前に最低限以下を提示する：

1. **どこに投稿するか**：リポジトリ名 / チャンネル名 / URL
2. **何を投稿するか**：タイトル・本文の**全文**（要約だけで済ませない）
3. **誰に通知が飛ぶか**：メンション先、CC、@channel 等
4. **不可逆性の有無**：編集可能か、削除できるか

### 例

> 以下のコメントを `mastra-ai/mastra#16429` に投稿してよいでしょうか？
>
> 宛先：メンテナー @roaminro。GitHub 通知が飛びます。後から編集・削除可能。
>
> ```
> Thanks @roaminro! Pushed a fix in 420c802...
> ```

みのるんが「OK」「いいよ」「投稿して」等と返したら、初めて実行する。

## 対象外（事前確認**しない**）

以下は対象外。**間違っても確認しない**（過剰確認は禁止）：

- **自分のリポジトリ**（minorun365 配下のリポ、自分のフォーク含む）への commit / push / branch 操作などローカル発の全操作
- **自分の dotfiles**（`work/dotfiles` 等）の同期
- **`~/.claude/` 同期スキル**（`/sync-claude-code-settings`、`/sync-codex-settings`、`/sync-dotfiles` 等）の実行
- ローカルファイルの編集・読み書き
- 読み取り専用 API（`gh pr view`、`gh api .../comments` の GET、`gh issue list`、検索系 MCP、`*_search_*` 等）
- みのるんが**直前のターンで明示依頼**した個別操作（その操作1回限り、再利用しない）

## アンチパターン

- ❌ Bash が自動許可されているので、流れで `gh pr comment` を打ってしまう
- ❌ 「礼儀として返信しておくべき」と判断して勝手に投稿する
- ❌ 「みのるんが満足するだろう内容だから」と先回りで投稿する
- ❌ コメント本文を要約だけ提示して、全文を見せずに「投稿していい？」と聞く
- ❌ 連結コマンド（`cd ... && gh pr comment ...`）で間接的に発信して確認をすり抜ける
- ❌ **自分の設定同期・dotfiles 操作・同期スキル実行まで確認に来てウザがられる**（過剰確認）
- ❌ 「念のため」と何でもかんでも確認する（読み取り系・自分リポ操作は確認不要）
