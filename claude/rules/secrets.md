# シークレット管理（1Password連携）

- `.env` は手動で値を書かない。**`.env.op` テンプレートから `op-sync` で生成**する
- `.env.op` には `op://Vault/Item/Field` 形式の参照と非シークレット設定値を書く → Git コミット OK
- `.env` は `.gitignore` で除外
- 1Password アカウント: 複数アカウントを用途別に使い分ける（例: `my.1password.com`）
- Vault 構成: 使用する Vault をアカウントごとに決めておく
- **Touch ID 操作の最小化**: 複数の `op` コマンドは1回にまとめる。確認用の `op item get` を安易に挟まない

## Touch ID が出る回数は「`op` を叩いた回数」そのもの

ユーザーは自分の作業中に Touch ID ダイアログを割り込まれる。**探索や確認のために `op` を何度も叩かない。一覧は1回だけダンプしてスクラッチへ保存し、絞り込みはローカルで何度でもやる。**

```bash
op item list --account <acct> --format json > "$SCRATCH/op-items.json"   # op を叩くのはここだけ
python3 - "$SCRATCH/op-items.json" <<'EOF'                               # 絞り込みは何度でもこのファイルへ
...
EOF
```

- **検索条件を外しても `op` を叩き直さない。** 保存済みJSONへ条件を変えて当て直す（条件が緩すぎて全件ヒット、は普通に起きる）
- **書き込み系（`delete` / `edit` / `create`）の成否は終了コードで判定する。** 直後に `op item get` や `op item list` で裏取りしない。`op` は成功時は無言、失敗時は非ゼロ＋エラー文を返すので、それで足りる
- **`for` ループで複数アカウントを回すと、回数はアカウント数ぶん増える。** どのアカウントのレコードかを先に当ててから叩く
- 「まず全体像を見よう」で `op account list` → `op item list` → `op item get` と積む癖をやめる。**目的のレコードが1件なら、叩くのは1回で済む**

## `op` を叩くときは音を鳴らす

Touch ID のダイアログは**無音で出る**。ユーザーが別の作業をしていると気づかず、タイムアウトするか誤って閉じられる。**`op` を含む Bash 呼び出しの先頭で音を鳴らし、通知を出す。**

```bash
afplay /System/Library/Sounds/Glass.aiff & osascript -e 'display notification "Touch ID をお願いします（何のため）" with title "1Password" sound name "Glass"'; op …
```

- `PushNotification` は代わりにならない。ターミナルが前面にあると `Not sent` で握りつぶされ、音も通知も出ない
- 通知と `op` を別の呼び出しに分けない。鳴ってからダイアログが出るまでに間が空く
- ループで回すときは、最初の `authorization timeout` で `break` する。無音のダイアログをもう一度出しても状況は変わらない

## `op` を叩く前に、CLI で取れないか確かめる

**クラウドのAPIキーは、たいてい各クラウドのCLIから無言で取れる。** 1Password に控えがあっても、そちらを先に叩くと Touch ID が出て、離席中のユーザーを止めてしまう。

```bash
# Google（Gemini API キー等）は Touch ID なしで取れる
gcloud services api-keys get-key-string "projects/<PJ>/locations/global/keys/<UID>" \
  --account=<アカウント> --format="value(keyString)"
```

- AWS は Secrets Manager / SSM パラメータストアからの取得、GitHub は `gh auth token` が同じ役割
- **1Password を叩くのは、どのCLIからも取れない値のときだけ**（サービス固有のトークン、他人が発行した鍵、ブラウザにしか無いもの）
