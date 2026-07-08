# Chrome DevTools MCP でのSPA/React操作

## Chrome DevTools MCP でのSPA/React操作

`mcp__chrome-devtools__*` ツールでブラウザを操作する際の React/SPA 固有のTips。

### React Controlled Input への値セット

通常の `fill()` や DOM の `.value =` 直接代入では React の state が更新されず、入力欄が変化しない。
**native setter を使って InputEvent をディスパッチ**することで React に変更を伝える：

```javascript
// evaluate_script 内で使うスニペット
const inputs = [...document.querySelectorAll('input')];
const target = inputs[N];  // 対象フィールドの index
const nativeSetter = Object.getOwnPropertyDescriptor(
  window.HTMLInputElement.prototype, 'value'
).set;
target.focus();
nativeSetter.call(target, '');
target.dispatchEvent(new Event('input', { bubbles: true }));
nativeSetter.call(target, '入力したい値');
target.dispatchEvent(new Event('input', { bubbles: true }));
```

### button 以外の要素クリック（div.tab、span.navigation-button等）

React コンポーネントで `div` や `span` にクリックハンドラが付いているケースでは、
`element.click()` だけでは発火しないことがある。
**マウスイベントを完全シーケンスでディスパッチ**するのが確実：

```javascript
const rect = target.getBoundingClientRect();
const x = rect.left + rect.width / 2;
const y = rect.top + rect.height / 2;
['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click'].forEach(type => {
  target.dispatchEvent(new MouseEvent(type, {
    bubbles: true, cancelable: true, view: window, clientX: x, clientY: y, button: 0
  }));
});
```

### `take_snapshot` の結果が大きすぎてエラー

A11y ツリーをフルに取得すると数千行になり、ツール結果が上限を超えてエラーになることがある。

**対策**: `take_screenshot` → `Read` で視覚確認した後、`evaluate_script` で対象要素を JavaScript でピンポイントに探す。

```javascript
// スナップショット代わりに JS でDOM要素を直接検索
() => {
  return [...document.querySelectorAll('button')]
    .filter(b => b.getBoundingClientRect().top < window.innerHeight)
    .map(b => ({
      text: b.textContent.trim().substring(0, 30),
      ariaLabel: b.getAttribute('aria-label'),
      top: Math.round(b.getBoundingClientRect().top)
    }));
}
```

### オートコンプリート候補の選択

フォームに文字を入れると候補リストが出る場合、**可視かつ座標が適切な要素**を探してクリック：

```javascript
() => {
  const all = [...document.querySelectorAll('li, div, button')];
  const target = all.find(el => {
    const t = el.textContent.trim();
    const rect = el.getBoundingClientRect();
    return t.includes('候補テキスト') && rect.top > 0 && rect.top < window.innerHeight;
  });
  if (target) { target.click(); return { clicked: true }; }
  return { clicked: false };
}
```

### ブラウザ拡張（1Password等）のフォーム干渉を回避する

1Password 等の拡張は React のフォーム state を非同期で上書きする。DevTools click/fill を連続呼び出しすると、拡張がラジオボタン状態をリセットしてバリデーションエラーになることがある。

**対策**: 一連の操作を `evaluate_script` で**同期的に連続実行**し、拡張の割り込み前に送信まで完了させる：

```javascript
async () => {
  const sleep = (ms) => new Promise(r => setTimeout(r, ms));

  // 1. ラジオ操作
  const radio = [...document.querySelectorAll('input[type="radio"]')]
    .find(r => r.closest('label')?.textContent?.includes('All packages'));
  if (radio && !radio.checked) radio.click();
  await sleep(100);

  // 2. 送信ボタンを即クリック（拡張の干渉前に）
  const btn = [...document.querySelectorAll('button')]
    .find(b => b.textContent?.trim() === 'Generate token');
  btn?.click();

  return { radioChecked: radio?.checked, submitted: !!btn };
}
```

React SPA のフォームでは、バリデーション失敗後に state がリセットされることがある。Submit 直前にラジオ・チェックボックスの状態を再確認してから送信するのが安全。

---

