# フロントエンド開発パターン

React/TypeScript/Tailwindを使ったフロントエンド開発の学びを記録する。

## Tailwind CSS v4

### Vite統合（ゼロコンフィグ）
```typescript
// vite.config.ts
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  plugins: [react(), tailwindcss()],
})
```

### カスタムカラー定義
```css
/* src/index.css */
@import "tailwindcss";

@theme {
  --color-brand-blue: #0e0d6a;
}
```

### カスタムグラデーション
```css
.bg-brand-gradient {
  background: linear-gradient(to right, #1a3a6e, #5ba4d9);
}
```

## React ストリーミングUI

### イミュータブル更新（必須）
```typescript
// NG: シャローコピーしてオブジェクト直接変更 → StrictModeで2回実行され文字がダブる
setMessages(prev => {
  const newArr = [...prev];
  newArr[newArr.length - 1].content += chunk;
  return newArr;
});

// OK: map + スプレッド構文でイミュータブルに更新
setMessages(prev =>
  prev.map((msg, idx) =>
    idx === prev.length - 1 && msg.role === 'assistant'
      ? { ...msg, content: msg.content + chunk }
      : msg
  )
);
```

### タブ切り替え時の状態保持
```tsx
// NG: 条件レンダリングだとアンマウント時に状態が消える
{activeTab === 'chat' ? <Chat /> : <Preview />}

// OK: hiddenクラスで非表示にすれば状態が保持される
<div className={activeTab === 'chat' ? '' : 'hidden'}>
  <Chat />
</div>
<div className={activeTab === 'preview' ? '' : 'hidden'}>
  <Preview />
</div>
```

## Marp Core（ブラウザ用）

### 基本的な使い方
```typescript
import Marp from '@marp-team/marp-core';

const marp = new Marp();
const { html, css } = marp.render(markdown);

// SVG要素を抽出（DOM構造を維持）
const parser = new DOMParser();
const doc = parser.parseFromString(html, 'text/html');
const svgs = doc.querySelectorAll('svg[data-marpit-svg]');
```

### スライド表示
```tsx
<style>{css}</style>
<div className="marpit w-full h-full [&>svg]:w-full [&>svg]:h-full">
  <div dangerouslySetInnerHTML={{ __html: svg.outerHTML }} />
</div>
```

**重要**: `section`だけ抽出するとCSSセレクタがマッチしない。`div.marpit > svg > foreignObject > section` 構造が必要。

### Tailwind CSSとの競合
Marpの`class: invert`とTailwindの`.invert`ユーティリティが競合する。

```css
/* src/index.css に追加 */
.marpit section.invert {
  filter: none !important;
}
```

### SVGのレスポンシブ対応（スマホ対応）

MarpのSVGは固定サイズ（1280x720px）の`width`/`height`属性を持っているため、スマホの狭い画面では見切れる。SVG属性を動的に変更して対応：

```typescript
const svgs = doc.querySelectorAll('svg[data-marpit-svg]');

return Array.from(svgs).map((svg, index) => {
  // SVGのwidth/height属性を100%に変更してレスポンシブ対応
  svg.setAttribute('width', '100%');
  svg.setAttribute('height', '100%');
  svg.setAttribute('preserveAspectRatio', 'xMidYMid meet');
  return { index, html: svg.outerHTML };
});
```

**ポイント**:
- `width`/`height`を`100%`に → 親要素にフィット
- `preserveAspectRatio="xMidYMid meet"` → アスペクト比維持で中央配置
- CSSの`!important`よりSVG属性の直接変更が確実

**汎用パターン**: 外部ライブラリが生成する固定サイズSVGをレスポンシブにする場合に有効

## SSEストリーミング処理

```typescript
const reader = response.body?.getReader();
const decoder = new TextDecoder();
let buffer = '';

while (true) {
  const { done, value } = await reader.read();
  if (done) break;

  buffer += decoder.decode(value, { stream: true });
  const lines = buffer.split('\n');
  buffer = lines.pop() || '';  // 不完全な行は次回に持ち越し

  for (const line of lines) {
    if (line.startsWith('data: ')) {
      const data = line.slice(6);
      if (data === '[DONE]') return;
      const event = JSON.parse(data);
      // イベント処理
    }
  }
}
```

## Amplify UI React

### Authenticator（認証UI）
```tsx
import { Authenticator } from '@aws-amplify/ui-react';
import '@aws-amplify/ui-react/styles.css';

function App() {
  return (
    <Authenticator>
      {({ signOut, user }) => (
        <main>
          <h1>Hello {user?.username}</h1>
          <button onClick={signOut}>Sign out</button>
        </main>
      )}
    </Authenticator>
  );
}
```

### 日本語化
```typescript
// main.tsx
import { I18n } from 'aws-amplify/utils';
import { translations } from '@aws-amplify/ui-react';

I18n.putVocabularies(translations);
I18n.setLanguage('ja');
```

### 認証画面のカスタマイズ（Header/Footer）

Cognito認証画面にアプリ名やプライバシーポリシーを表示する：

```tsx
const authComponents = {
  Header() {
    return (
      <div className="text-center py-4">
        <h1 className="text-2xl font-bold text-gray-800">アプリ名</h1>
        <p className="text-sm text-gray-500 mt-1">
          「Create Account」で誰でも利用できます！
        </p>
      </div>
    );
  },
  Footer() {
    return (
      <div className="text-center py-3 px-4">
        <p className="text-xs text-gray-400 leading-relaxed">
          登録されたメールアドレスは認証目的でのみ使用します。
        </p>
      </div>
    );
  },
};

<Authenticator components={authComponents}>
  {({ signOut }) => <MainApp signOut={signOut} />}
</Authenticator>
```

**用途例**:
- Header: アプリ名、利用ガイド、ロゴ
- Footer: プライバシーポリシー、免責事項、メールアドレスの利用目的

### 認証画面の配色カスタマイズ（CSS方式）

`createTheme`/`ThemeProvider`ではグラデーションが使えないため、CSSで直接スタイリングするのが確実。

```css
/* src/index.css */

/* プライマリボタン（グラデーション対応） */
[data-amplify-authenticator] .amplify-button--primary {
  background: linear-gradient(to right, #1a3a6e, #5ba4d9);
  border: none;
}

[data-amplify-authenticator] .amplify-button--primary:hover {
  background: linear-gradient(to right, #142d54, #4a93c8);
}

/* リンク（パスワードを忘れた等） */
[data-amplify-authenticator] .amplify-button--link {
  color: #1a3a6e;
}

/* タブ */
[data-amplify-authenticator] .amplify-tabs__item--active {
  color: #1a3a6e;
  border-color: #5ba4d9;
}

/* 入力フォーカス */
[data-amplify-authenticator] input:focus {
  border-color: #5ba4d9;
  box-shadow: 0 0 0 2px rgba(91, 164, 217, 0.2);
}
```

**ポイント**:
- `[data-amplify-authenticator]`セレクタで認証画面のみに適用
- `createTheme`はグラデーション非対応 → CSS直接指定が確実
- アプリ本体と同じ配色を使用して統一感を出す

## ステータス表示パターン

### 重複防止（ツール使用イベント）

LLMのストリーミングでは、同じツールに対して複数の`tool_use`イベントが送信されることがある。
ステータスメッセージの重複を防ぐには、追加前に既存チェックが必要。

```typescript
onToolUse: (toolName) => {
  if (toolName === 'output_slide') {
    setMessages(prev => {
      // 既存のステータスがあればスキップ
      const hasExisting = prev.some(
        msg => msg.isStatus && msg.statusText === 'スライドを生成中...'
      );
      if (hasExisting) return prev;
      return [
        ...prev,
        { role: 'assistant', content: '', isStatus: true, statusText: 'スライドを生成中...' }
      ];
    });
  }
},
```

### 複数ステータスのアイコン切り替え

完了状態のステータスが複数ある場合、OR条件でチェックマークを表示。

```tsx
// NG: 1つの完了状態のみ
{message.statusText === '生成しました' ? <CheckIcon /> : <Spinner />}

// OK: 複数の完了状態に対応
{message.statusText === '生成しました' || message.statusText === '検索完了' ? (
  <span className="text-green-600">✓</span>
) : (
  <span className="animate-spin">◌</span>
)}
```

### ステータス遷移の連動

前のステータスを完了に更新しつつ、新しいステータスを追加する場合。

```typescript
// Web検索 → スライド生成 の遷移例
if (toolName === 'output_slide') {
  setMessages(prev => {
    // Web検索中を完了に更新
    const updated = prev.map(msg =>
      msg.isStatus && msg.statusText === 'Web検索中...'
        ? { ...msg, statusText: 'Web検索完了' }
        : msg
    );
    // 新しいステータスを追加
    return [
      ...updated,
      { role: 'assistant', content: '', isStatus: true, statusText: 'スライドを生成中...' }
    ];
  });
}
```

## Marp Coreカスタムテーマ

### テーマの追加方法

```typescript
import Marp from '@marp-team/marp-core';
import customTheme from '../themes/custom.css?raw';  // Viteの?rawでCSSを文字列として読み込み

const marp = new Marp();
marp.themeSet.add(customTheme);  // カスタムテーマを登録
const { html, css } = marp.render(markdown);
```

### コミュニティテーマの利用

Marpコミュニティテーマ（例: border）を使う場合:
1. CSSファイルをダウンロード
2. `src/themes/` に配置
3. `?raw` サフィックスでインポート
4. `marp.themeSet.add()` で登録

**参考**: https://rnd195.github.io/marp-community-themes/

### フロントエンドとバックエンドの両方に配置

カスタムテーマを使う場合、以下の両方に配置が必要:
- `src/themes/xxx.css` - フロントエンド（Marp Core）用
- `amplify/agent/runtime/xxx.css` - バックエンド（Marp CLI PDF生成）用

PDF生成時は `--theme` オプションでCSSファイルを指定:
```python
cmd = ["marp", md_path, "--pdf", "--theme", str(theme_path)]
```
