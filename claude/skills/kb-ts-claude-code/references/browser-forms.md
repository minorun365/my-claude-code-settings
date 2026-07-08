# Chrome DevTools and browser form automation

## 目次

- Chrome DevTools MCP: macOSでログイン済みChromeを操作する
  - 推奨: autoConnect（Chrome 144+、再起動不要）
  - フォールバック: デバッグ専用プロファイル + `--browserUrl`（Chrome 143以前）
- Chrome DevTools MCP: Reactフォームで `fill` の値が消える
  - 症状
  - 原因
  - 解決策: `evaluate_script` でnativeセッター + イベント発火
- Chrome DevTools MCP: 基本操作フローとa11yツリーに出ない要素の操作
  - 基本操作フロー
  - a11yツリーに出ない要素（`<span>` ボタン等）の操作
  - インライン編集UIサイトの操作パターン
- Chrome DevTools MCP: 大量フォーム自動化（複数注文・複数登録）の context 節約
  - 戦略: `evaluate_script` 内の JS polling で `wait_for` を代替する
  - iframe 内の要素操作（contentDocument 経由）
  - div/span がクリック対象の罠 → leaf-search パターン
  - navigate を伴うクリックは別 evaluate に分割
  - Web フォーム自動入力時の罠（手動操作も同じ）
- マークダウンプレビュー（mdserve / glow）

## Chrome DevTools MCP: macOSでログイン済みChromeを操作する

### 推奨: autoConnect（Chrome 144+、再起動不要）

Chrome 144以降、`chrome://inspect/#remote-debugging` UIが追加され、実行中のChromeに再起動なしで接続できるようになった。

**手順：**
1. ユーザーに Chrome で `chrome://inspect/#remote-debugging` を開いてもらい、トグルをオンにしてもらう（初回のみ、設定は保持される）
2. Chrome DevTools MCP ツール（`list_pages` 等）を呼ぶと Chrome に接続許可ダイアログが表示される
3. ユーザーに「許可」をクリックしてもらう → 接続完了

**MCP設定（`~/.claude.json`）:**
```json
{
  "type": "stdio",
  "command": "npx",
  "args": ["-y", "chrome-devtools-mcp@latest", "--autoConnect"]
}
```

**メリット：**
- Chromeの再起動不要、ログイン状態・拡張機能・タブすべてそのまま
- 別プロファイル（`--user-data-dir`）不要
- JAMF管理端末でも動作確認済み

**既知の注意点：**
- `--autoConnect` と `--browserUrl` は排他的（併用不可）
- 長時間セッションで接続が切れることがある → 再度ダイアログが表示されるので再許可
- Chrome 144未満では利用不可（フォールバック方式を使う）

### フォールバック: デバッグ専用プロファイル + `--browserUrl`（Chrome 143以前）

autoConnect が使えない場合のみ、以下の従来方式を使う。

**1. Chrome起動コマンド:**
```bash
pkill -9 "Google Chrome"
sleep 2
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
  --remote-debugging-port=9222 \
  --user-data-dir="$HOME/.chrome-debug-profile" &
```

- 普段のプロファイルとは別なのでログイン状態は初期状態
- 初回は1Password拡張のインストール＋各サービスにログインが必要

**2. MCP設定:**
```json
{
  "type": "stdio",
  "command": "npx",
  "args": ["-y", "chrome-devtools-mcp@latest", "--browserUrl", "http://127.0.0.1:9222"]
}
```

---

## Chrome DevTools MCP: Reactフォームで `fill` の値が消える

### 症状

`mcp__chrome-devtools__fill` でテキストを入力した後、別の要素をクリック・ラジオボタン変更・送信ボタン押下などを行うと、入力した値がクリアされる。

### 原因

`fill` ツールはDOMの `value` プロパティを直接書き換えるが、Reactは内部ステート（Fiber）で値を管理しているため、React側のステートが空のまま。Reactの再レンダリングが走ると内部ステートの空文字でDOMが上書きされる。AWS Pulse等のReactベースのフォームで発生。

### 解決策: `evaluate_script` でnativeセッター + イベント発火

ReactはHTMLElement の native setter を経由した変更 + `input` イベントでステートを同期する。以下のパターンを使う：

**単一フィールド（UIDで指定）:**
```javascript
// args: ["uid_of_element"]
(el) => {
  const setter = Object.getOwnPropertyDescriptor(
    window.HTMLTextAreaElement.prototype, 'value').set;
  setter.call(el, "入力テキスト");
  el.dispatchEvent(new Event('input', { bubbles: true }));
  el.dispatchEvent(new Event('change', { bubbles: true }));
  return el.value.length;
}
```

**一括入力（インデックスで指定）:**
```javascript
() => {
  const setter = Object.getOwnPropertyDescriptor(
    window.HTMLTextAreaElement.prototype, 'value').set;
  const tas = document.querySelectorAll('textarea');
  const values = { 0: "テキスト1", 3: "テキスト2" }; // インデックス: 値
  for (const [idx, text] of Object.entries(values)) {
    const ta = tas[parseInt(idx)];
    setter.call(ta, text);
    ta.dispatchEvent(new Event('input', { bubbles: true }));
    ta.dispatchEvent(new Event('change', { bubbles: true }));
  }
  return 'done';
}
```

**注意:**
- `<input>` の場合は `HTMLInputElement.prototype` を使う
- `fill` は非Reactサイトや単純なHTMLフォームでは問題なく動作する
- Reactサイトかどうかは `document.querySelector('[data-reactroot], #__next, #root')` で判定可能

---

## Chrome DevTools MCP: 基本操作フローとa11yツリーに出ない要素の操作

### 基本操作フロー

```
list_pages
  → select_page（対象タブを選択）
    → take_snapshot（a11yツリーでuid取得）
      → click / fill（uid指定で操作）
        → take_screenshot（確認）
```

### a11yツリーに出ない要素（`<span>` ボタン等）の操作

Connpass の「イベント作成」ボタンのように `<span>` タグで作られたインタラクティブ要素は、a11yツリーでは `StaticText` として認識され `click` ツールで直接操作できない。

**症状の見分け方**: `take_snapshot` の結果で `uid=X_Y StaticText "ボタン名"` になっている（`button` や `link` ではない）。

**解決策**: `evaluate_script` でDOM直接操作する。

```javascript
// セレクタで要素を探してクリック
() => {
  const btn = document.querySelector('span.EventCreate');
  if (btn) { btn.click(); return 'clicked!'; }
  return 'not found';
}
```

**要素探索のコツ**: a11yツリーでは見えないので、まず `evaluate_script` でクラス名・テキスト・イベント有無を調べる。

```javascript
// 「ボタンテキスト」を含む要素の親チェーン（クラス名・タグ名等）を取得
() => {
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  const results = [];
  while (walker.nextNode()) {
    if (walker.currentNode.textContent.trim() === 'ボタンテキスト') {
      let el = walker.currentNode.parentElement;
      const chain = [];
      for (let i = 0; i < 4 && el; i++) {
        chain.push({ tag: el.tagName, className: el.className, href: el.href || '' });
        el = el.parentElement;
      }
      results.push(chain);
    }
  }
  return results;
}
```

### インライン編集UIサイトの操作パターン

Connpass のような「クリックで編集モード → 個別保存」方式のサイトでは：

1. `click` でフィールドをクリック → 編集モードになる（`textbox` が出現）
2. `take_snapshot` を再度取得（新しいuidが生成される）
3. `fill` で値を入力
4. `click` で保存ボタンをクリック
5. `take_screenshot` で保存されたか確認

**注意**: 編集モードに入るとスナップショットのuidが変わる（例: `uid=4_*` → `uid=5_*`）。必ず編集モードに入ってから再取得すること。

---

## Chrome DevTools MCP: 大量フォーム自動化（複数注文・複数登録）の context 節約

ECサイト購入を13回繰り返す等、**同じフロー × N回**を1セッションで完走させたいときの設計指針。素直に `take_snapshot` / `wait_for` を毎回使うと、フッターのカテゴリメニュー（数百行のa11yツリー）が毎回 context に取り込まれ、5〜6件目で `Prompt is too long` で中断する。

### 戦略: `evaluate_script` 内の JS polling で `wait_for` を代替する

`mcp__chrome-devtools__wait_for` はマッチした瞬間のページ全体スナップショットを返すため、巨大ナビゲーションを毎ステップ吸い込んでしまう。代わりに `evaluate_script` の async 関数内で polling し、**必要な情報だけJSON で返す**：

```javascript
async () => {
  const wait = (ms) => new Promise(r => setTimeout(r, ms));
  for (let i = 0; i < 30; i++) {
    await wait(500);
    if (location.href.includes('/checkout/confirm')
      && document.body.innerText.includes('ご注文内容の確認')) break;
  }
  // 必要な情報だけ抽出して返す（フッターメニュー等を取り込まない）
  const text = document.body.innerText;
  return {
    size: text.match(/サイズ:\s*([SMLX]+)/)?.[1],
    total: text.match(/合計\s*([\d,]+\s*円)/)?.[1],
  };
}
```

これで context 消費が wait_for の **1/10程度** に圧縮される。

### iframe 内の要素操作（contentDocument 経由）

同一オリジンの iframe（モーダル等）は `iframe.contentDocument` 経由で JS から直接操作できる。a11y ツリーの uid を取得して `fill` する代わりに：

```javascript
const iframe = document.querySelector('iframe');
const idoc = iframe?.contentDocument;
const inputs = idoc?.querySelectorAll('input.quantityInput');
inputs[2].value = '1';
inputs[2].dispatchEvent(new Event('input', { bubbles: true }));
inputs[2].dispatchEvent(new Event('change', { bubbles: true }));
```

iframe ロード待ちは「目的の要素が出現するまで polling」が確実：

```javascript
let inputs;
for (let i = 0; i < 30; i++) {
  await wait(500);
  inputs = document.querySelector('iframe')?.contentDocument?.querySelectorAll('input.quantityInput');
  if (inputs?.length === 6) break;
}
```

### div/span がクリック対象の罠 → leaf-search パターン

jQuery UI や独自コンポーネント実装のサイトでは、「ご注文カートへ」「カートへ進む」のような操作要素が `<button>` や `<a>` ではなく `<div class="addCartLink">` や `<span class="ui-button-text">` で実装されていることがある。`querySelectorAll('button, a')` では拾えない。

→ **leaf-search**（children なし & innerText 完全一致）で要素を特定し、必要なら親 button/a までたどる：

```javascript
for (const el of idoc.querySelectorAll('*')) {
  if (el.children.length > 0) continue;  // リーフ要素のみ
  if ((el.innerText || '').trim() === 'カートへ進む') {
    let target = el;
    while (target && !['BUTTON', 'A'].includes(target.tagName)) target = target.parentElement;
    (target || el).click();
    break;
  }
}
```

### navigate を伴うクリックは別 evaluate に分割

`evaluate_script` 内で `click()` がページ navigate を発生させる場合、その後の `await wait()` 中に JS context が破棄されて undefined error になることがある。**navigate trigger の click は evaluate の最後**にし、次の evaluate で URL polling して着地確認する。

具体的には1件あたり以下の5分割が安定：

1. **evaluate 1**: モーダル開く → サイズ入力 → 「カートへ進む」click（ここで親 navigate）
2. **evaluate 2**: URL polling でカート画面着地確認 → 「ご注文手続きへ進む」click
3. **evaluate 3**: 入力フォームの全項目を JS 一括設定 → 「入力内容のご確認」click
4. **evaluate 4**: 確認画面 polling → 必要項目を JSON 抽出 → 「注文する」click
5. **evaluate 5**: 完了画面 polling → 注文番号抽出

### Web フォーム自動入力時の罠（手動操作も同じ）

EC・登録フォームには、自動化でも手動でも引っかかりやすい初期値の罠がある：

- **「お届け先リストに登録する」「メルマガ配信を希望する」がデフォルト ON**：1回限りの操作なら必ず外す
- **「お届け先」が「ご注文者と同じ」（自分の住所）に初期セット**：第三者宛なら必ず「新規入力」に切り替える
- **クレジットカードは登録カード ラジオが未選択状態**：明示的に選択しないと「新しいカード」入力欄が出てきてしまう

13回繰り返しの自動化スクリプトには、これらの「デフォルト解除/選択」を **必ず JS の最初に組み込む**。1件目のサンプル時にチェックして「型」に入れておく。

---

## マークダウンプレビュー（mdserve / glow）

- みのるんがマークダウンをきれいに見たいときは mdserve をバックグラウンドで起動してブラウザで開く
- **現行の正しい起動方法**（2026年4月確認済み）:
  - CLI 仕様が変更され、`-d <dir>` フラグは廃止。`<PATH>` 位置引数に変更
  - `-o` フラグでブラウザを自動オープン（`open` コマンド不要）
  - ライブリロード対応（ファイル編集が即座にブラウザに反映）
  ```bash
  # バックグラウンドで起動（-o でブラウザ自動オープン）
  mdserve -p 8080 -o ~/path/to/file.md &
  # またはディレクトリ全体を serve（ファイル一覧表示）
  mdserve -p 8080 -o ~/path/to/docs/ &
  ```
- **旧コマンド（廃止済み・使用不可）**:
  ```bash
  # NG: -d フラグは存在しない
  mdserve -d <ディレクトリ> -p 8080
  ```
- ターミナルで手軽に確認したい場合は `glow <ファイル>` も使える（v2.1.1 インストール済み）

---
