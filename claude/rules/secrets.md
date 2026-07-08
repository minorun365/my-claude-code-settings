# シークレット管理（1Password連携）

- `.env` は手動で値を書かない。**`.env.op` テンプレートから `op-sync` で生成**する
- `.env.op` には `op://Vault/Item/Field` 形式の参照と非シークレット設定値を書く → Git コミット OK
- `.env` は `.gitignore` で除外
- 1Password アカウント: 複数アカウントを用途別に使い分ける（例: `my.1password.com`）
- Vault 構成: 使用する Vault をアカウントごとに決めておく
- **Touch ID 操作の最小化**: 複数の `op` コマンドは1回にまとめる。確認用の `op item get` を安易に挟まない
- 詳細な `op` CLI の操作方法は `/kb-1password-cli` を参照
