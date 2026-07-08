# Git関連

- **リポジトリ配下のファイル変更・追加・コピーが完了したら、stage → commit → push まで確認なしで一気に完結する**。「これで commit していい？」「push してもいい？」と聞かない。リモートが進んでいる場合は `git pull --ff-only` で取り込んでから push。例外は `outbound-communication.md` で事前確認必須とされている発信操作のみ
- 作業が長引く場合も、意味のある区切りごとに小さく commit → push してリモートへ退避する。こまめな自動 push を標準運用とする
- git commit 後は特に指示がなくても必ず push まで行う（stage → commit → push を1セットとする）
- コミットメッセージは1行の日本語でシンプルに
- ブランチの切り替えには `git switch` を使う（`git checkout` は古い書き方）
- 新規ブランチ作成は `git switch -c ブランチ名`
- GHE push で 403 → まず VPN 接続を確認。詳細は `/kb-ts-claude-code` を参照
- `gh repo create` に `--hostname` フラグは存在しない。`GH_HOST` 環境変数で指定すること

## GitHub Issue / PR のコメントルール

- Issue や PR にコメントする際は、**必ず関係者をメンション**すること（通知が届かないため）
- 誰にメンションすべきか迷う場合は、みのるんに確認してから投稿する
