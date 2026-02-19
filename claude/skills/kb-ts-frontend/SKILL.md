---
name: kb-ts-frontend
description: フロントエンドトラブルシューティング。Web Audio/Tailwind/OGP/React/SSE/SNS連携等
user-invocable: true
---

# フロントエンド トラブルシューティング

フロントエンド関連で遭遇した問題と解決策を記録する。

## Web Audio API: AudioContext({ sampleRate: 16000 }) が macOS で不安定

**症状**: `new AudioContext({ sampleRate: 16000 })` で作成した AudioContext で音声再生が不安定（ノイズ、途切れ、無音）

**原因**: macOS のオーディオハードウェアは通常 48kHz で動作する。16kHz を強制するとドライバレベルで不安定になる

**解決策**: AudioContext はネイティブサンプルレートで作成し、`createBuffer(1, length, 16000)` でソースの sampleRate を指定する

```typescript
// NG: sampleRate を 16kHz に強制
const ctx = new AudioContext({ sampleRate: 16000 });

// OK: ネイティブサンプルレート + AudioBuffer で 16kHz を指定
const ctx = new AudioContext(); // ネイティブ（通常 48kHz）
const buffer = ctx.createBuffer(1, data.length, 16000); // 16kHz として解釈
// Web Audio API が自動でリサンプリング（16kHz → 48kHz）
```

## Web Audio API: ブラウザで音が出ない（自動再生ポリシー）

**症状**: AudioBufferSourceNode で音声を再生しようとしても無音

**原因**: ブラウザの自動再生ポリシーにより、ユーザーインタラクションなしでは AudioContext が `suspended` 状態になる

**解決策**: ユーザーのボタンクリック等のタイミングで `AudioContext.resume()` を呼ぶ

```typescript
const handleStartCall = async () => {
  await audioContext.resume(); // 必須！これがないと音が出ない
  // ... WebSocket接続等
};
```

## Nova Sonic トランスクリプト: 吹き出しが重複表示

**症状**: アシスタントの応答が吹き出しで2回表示される

**原因**: `isFinal=false` のときだけ直前エントリを上書きしていたため、`isFinal=true` が来ると新しいエントリとして追加され、同じ応答が2つ表示された

**解決策**: `isFinal` の値に関わらず、直前エントリが同じロールで `isFinal=false` なら上書き

```typescript
setTranscripts(prev => {
  const last = prev[prev.length - 1];
  if (last && last.role === role && !last.isFinal) {
    return [...prev.slice(0, -1), { role, text, isFinal }];
  }
  return [...prev, { role, text, isFinal }];
});
```

## Tailwind CSS v4: dev サーバーでユーティリティクラスが生成されない

**症状**: `npx vite` の dev サーバーで Tailwind のユーティリティクラスが一切生成されない。ビルドでは正常

**診断方法**: ブラウザの DevTools で CSS を確認
- 正常: 先頭が `/*! tailwindcss v4.x.x | MIT License */`
- 異常: 先頭が `@layer theme, base, components, utilities;`

**原因**: `@tailwindcss/vite` プラグインの `transform` ハンドラーが Vite 7 の dev サーバーモードで呼ばれない場合がある

**解決策**: `@tailwindcss/postcss`（PostCSS 方式）に切り替える

```javascript
// postcss.config.js（新規作成）
export default {
  plugins: {
    '@tailwindcss/postcss': {},
  },
}
```

```typescript
// vite.config.ts から @tailwindcss/vite を削除
export default defineConfig({
  plugins: [react()],  // tailwindcss() を削除
})
```

## OGP/Twitterカード: 画像が表示されない

**症状**: TwitterでURLをシェアしてもカード画像が表示されない

**解決策チェックリスト**:

1. **metaタグ（必須）**
   - [x] `og:image` は絶対URL（`https://`から始まる）
   - [x] `og:url` でサイトURLを明示
   - [x] `og:image:secure_url` / `og:image:width` / `og:image:height` / `og:image:type` を追加

2. **Twitter専用タグ（必須）**
   - [x] `twitter:card` は `summary`（小）か `summary_large_image`（大）
   - [x] `twitter:image` / `twitter:title` / `twitter:description` を明示的に指定

3. **画像ファイル**
   - [x] 5MB以下
   - [x] `summary` なら正方形（512x512推奨）、`summary_large_image` なら横長（1200x630推奨）
   - [x] Exifメタデータを削除（iPhoneで撮った画像は要注意）
   - [x] HTTPSで配信

4. **キャッシュ対策**
   - [x] 画像URLにバージョンパラメータ追加（`?v=2` など）
   - [x] [Twitter Card Validator](https://cards-dev.twitter.com/validator) で再検証

**注意**: Twitterカードのキャッシュは最大7日間保持される。

## React StrictMode: 文字がダブって表示される

**症状**: ストリーミングUIで文字が2回表示される

**原因**: StrictModeで2回実行される際、シャローコピーしたオブジェクトを直接変更していた

**解決策**: イミュータブルな更新を使用
```typescript
// NG
setMessages(prev => {
  const newArr = [...prev];
  newArr[newArr.length - 1].content += chunk;
  return newArr;
});

// OK
setMessages(prev =>
  prev.map((msg, idx) =>
    idx === prev.length - 1 ? { ...msg, content: msg.content + chunk } : msg
  )
);
```

## SSE: チャットの吹き出しが空のまま

**症状**: APIは成功（200）だが、UIに内容が表示されない

**原因**: APIは`event.data`を返すが、コードは`event.content`を期待していた

**解決策**: 両方に対応
```typescript
const textValue = event.content || event.data;
```

## 疑似ストリーミング: エラーメッセージが表示されない

**症状**: `onError`コールバックで疑似ストリーミングを開始しても、メッセージが表示されない

**原因**: `onError`内の非同期関数が`await`されずに呼ばれ、`finally`ブロックが先に実行される。`finally`で`isStreaming: false`に設定されるため、ストリーミングループ内の`isStreaming`チェックが失敗する。

**解決策**: 疑似ストリーミングのループ内で`isStreaming`チェックを緩和する

```typescript
// NG: isStreamingをチェック（finallyで先にfalseになる）
idx === prev.length - 1 && msg.role === 'assistant' && msg.isStreaming

// OK: isStreamingチェックを削除
idx === prev.length - 1 && msg.role === 'assistant'
```

## Twitter/Xシェア: ツイートボックスにテキストが入力されない

**症状**: シェアリンクをクリックしてTwitterを開いても、ツイートボックスにテキストが何も入力されていない

**原因**: `https://x.com/compose/post?text=...` 形式を使用していた。この形式はXのWeb UI直接アクセス用で、`text`パラメータが無視されることがある

**解決策**: Twitter Web Intent形式を使用する

```python
# NG: compose/post形式（textパラメータが無視される）
url = f"https://x.com/compose/post?text={encoded_text}"

# OK: Web Intent形式（textパラメータが確実に反映される）
url = f"https://twitter.com/intent/tweet?text={encoded_text}"
```

## デバッグTips

### Chrome DevTools MCP

ブラウザの問題を調査する際は、Chrome DevTools MCPを使用：
1. `list_console_messages` - コンソールエラー確認
2. `list_network_requests` - API呼び出し確認
3. `get_network_request` - リクエスト/レスポンス詳細確認

### Marp関連

Marp関連のトラブルシューティングは `/kb-marp` スキルを参照。
