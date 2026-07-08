# GAS, freebusy, Slides, and references

## 目次

- clasp（GAS CLI）複数アカウント認証
  - 認証の仕組み
  - 複数アカウントの切り替え手順
  - 認証エラー時の対処
  - push が Skipping になる場合
- Google Apps Script (GAS) Web App の落とし穴
  - clasp deploy では Web App の公開設定が正しく反映されない
  - Web App の初回使用前に OAuth 承認が必要
  - GAS を定期キャッシュ + Web API として使うパターン
- 会議調整：複数人の空き時間確認（query_freebusy）
  - 使い方の例（20:00〜21:00 JST の空き確認）
  - 結果の見方
  - 注意事項
- Google Slides のコンテンツ取得（2026年4月確認）
  - Slides API が無効でも Drive API で代替できる
  - `get_presentation` ツールを使う場合
- 参考リンク

## clasp（GAS CLI）複数アカウント認証

GAS を複数の Google アカウントで管理する場合の手順。

### 認証の仕組み

clasp は `~/.clasprc.json` にトークンを保存する。**`clasp login` を実行するたびに上書きされる**ため、複数アカウントで push/deploy したいときは都度ログインし直す必要がある。

### 複数アカウントの切り替え手順

```bash
# アカウントA用 GAS
cd gas/project-a
npx @google/clasp login        # ブラウザでアカウントAでログイン
npx @google/clasp push --force # 最新コードを push
npx @google/clasp deploy --description "本番"

# アカウントB用 GAS
cd ../project-b
npx @google/clasp login        # ブラウザでアカウントBでログイン
npx @google/clasp push --force # 最新コードを push
npx @google/clasp deploy --description "本番"
```

> ⚠️ **Chrome プロファイルに注意**: `clasp login` でブラウザが開いたとき、対象アカウントの正しいプロファイル（ログイン中のアカウント）を使うこと。間違えると認証トークンが別アカウントのもので上書きされる。
> Claude Code が clasp コマンドを実行するときは、**事前に「どちらのアカウントで認証するか」を声に出してから実行すること。**

### 認証エラー時の対処

`invalid_grant` や `reauth related error (invalid_rapt)` が出た場合は、認証トークンの期限切れ。`clasp login` を再実行して認証し直す。

```
{"error":"invalid_grant","error_description":"reauth related error (invalid_rapt)"}
→ npx @google/clasp login を再実行
```

### push が Skipping になる場合

変更がないとみなされて `Skipping push.` と表示されることがある。`--force` を付けることで強制的に push できる：

```bash
npx @google/clasp push --force
```

---

## Google Apps Script (GAS) Web App の落とし穴

GAS を外部 API（AgentCore 等）から呼ばれる Web API として使う場合の注意点。

### clasp deploy では Web App の公開設定が正しく反映されない

**症状:** `clasp deploy` でデプロイした URL にアクセスすると「ドライブ - 現在、ファイルを開くことができません。」エラーが出る。

**原因:** `appsscript.json` に `"access": "ANYONE_ANONYMOUS"` を記述しても、`clasp deploy` ではウェブアプリとして正しく公開されないことがある（特に Google Workspace 組織アカウントの場合）。

**解決策:** GAS エディタの UI から手動でデプロイする。
1. GAS エディタ → 右上「デプロイ」→「**新しいデプロイ**」
2. 種類: **ウェブアプリ**
3. 次のユーザーとして実行: **自分**
4. アクセスできるユーザー: **全員（匿名ユーザーを含む）**
5. 「デプロイ」して表示された新しい URL を使う

→ `clasp deploy` で発行した URL は廃棄して、UI デプロイの URL に差し替える。

### Web App の初回使用前に OAuth 承認が必要

**原因:** GAS が Gmail 等にアクセスする権限をまだ持っていない。

**解決策:** GAS エディタで対象の関数（例: `updateGmailCache`）を一度手動実行し、OAuth 承認ダイアログを完了させてから Web App にアクセスする。

### GAS を定期キャッシュ + Web API として使うパターン

AgentCore 等の外部サービスから Gmail 等のデータを取得したい場合、直接 OAuth 認証が難しいケースがある。GAS を中継レイヤーとして使う方式が有効：

1. GAS が Gmail を定期取得してキャッシュ（Script Properties）
2. 外部サービスはトークン付き URL で GAS Web API を叩いてキャッシュを取得
3. GAS トリガーで定期更新（時間ベーストリガー → 毎時実行）

```javascript
// GAS 側: キャッシュ取得・公開
function doGet(e) {
  const props = PropertiesService.getScriptProperties();
  const token = props.getProperty("API_TOKEN");
  if (e?.parameter?.token !== token) {
    return ContentService.createTextOutput(JSON.stringify({ error: "Unauthorized" }))
      .setMimeType(ContentService.MimeType.JSON);
  }
  const cache = props.getProperty("GMAIL_CACHE");
  return ContentService.createTextOutput(cache).setMimeType(ContentService.MimeType.JSON);
}
```

---

## 会議調整：複数人の空き時間確認（query_freebusy）

`query_freebusy` は Google Calendar の FreeBusy API を使い、空き/ビジー情報をまとめて取得できる。


- 予定の詳細（タイトル）は見えないが「この時間はビジー」という情報は取れる
- **自分以外のカレンダーに直接アクセス権がなくても使える**（同組織内なら可）
- 最大50カレンダーを一度に照会できる（`calendar_expansion_max: 50`）

### 使い方の例（20:00〜21:00 JST の空き確認）

```
mcp__google-workspace__query_freebusy:
  user_google_email: <メールアドレス>
  time_min: 2026-04-13T20:00:00+09:00
  time_max: 2026-04-17T21:00:00+09:00
  calendar_ids:
    - <メールアドレス>
```

### 結果の見方

- UTC で返ってくるので JST に変換して判定（+9時間）
- `busy periods` に含まれない時間帯 = 空き
- 週末・祝日は業務時間外のため空きになりがちだが、夜間帯の平日は要注意

### 注意事項


---

## Google Slides のコンテンツ取得（2026年4月確認）

### Slides API が無効でも Drive API で代替できる

Google Slides API（`slides.googleapis.com`）は Google Cloud プロジェクトで明示的に有効化する必要があり、デフォルトは無効。有効化していない場合は 403 エラーになる。

**エラー例:**
```
Google Slides API has not been used in project XXXXXXXXXX before or it is disabled.
Enable it by visiting https://console.developers.google.com/apis/api/slides.googleapis.com/overview
```

**代替手段: `get_drive_file_content` で Slides のテキストを取得できる**

```
mcp__google-workspace__get_drive_file_content(
  user_google_email="<メールアドレス>",
  file_id="<presentationId>"
)
```

- MIME タイプ `application/vnd.google-apps.presentation` のファイルに対して Drive API 経由でテキストエクスポートが行われる
- スライドのテキスト・ノートは取得可能
- 画像・図形・デザイン情報は取得不可（テキストのみ）
- Google Slides API を有効化しなくても動作する

### `get_presentation` ツールを使う場合

`mcp__google-workspace__get_presentation` は Slides API を使用するため、GCP プロジェクトで事前に Slides API を有効化する必要がある。Drive API だけでテキスト内容を取れる場合は `get_drive_file_content` で十分。

---

## 参考リンク

- [taylorwilsdon/google_workspace_mcp](https://github.com/taylorwilsdon/google_workspace_mcp)
- [aaronsb/google-workspace-mcp](https://github.com/aaronsb/google-workspace-mcp)
- [Google Auth Platform の概要](https://support.google.com/cloud/answer/15544987)
- [Audience 設定（テストモード/本番）](https://support.google.com/cloud/answer/15549945)
- [OAuth Clients 管理](https://support.google.com/cloud/answer/15549257)
- [Gmail API スコープ一覧](https://developers.google.com/workspace/gmail/api/auth/scopes)
