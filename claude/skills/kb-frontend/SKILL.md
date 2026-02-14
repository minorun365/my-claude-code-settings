---
name: kb-frontend
description: フロントエンド開発のナレッジ。React/Tailwind/SSE/Amplify UI等（Marpは /kb-marp）
user-invocable: true
---

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

### ステータス表示の更新パターン（1つだけ表示）

複数のステータスが表示されないよう、新しいステータスを追加する前に古いものを削除する：

```typescript
setMessages(prev => {
  // 既存の進行中ステータス（完了以外）を削除
  const filtered = prev.filter(
    msg => !(msg.isStatus && msg.statusText?.startsWith('検索中') && msg.statusText !== '検索完了')
  );
  // 新しいステータスを追加
  return [
    ...filtered,
    { role: 'assistant', content: '', isStatus: true, statusText: newStatus }
  ];
});
```

### フェードインアニメーションの発火（keyを変える）

Reactでは `key` が変わると要素が再マウントされる。これを利用してアニメーションを発火：

```tsx
// keyにステータス内容を含めることで、内容が変わるたびにフェードインが発火
<div
  key={isSearching ? `search-${statusText}` : index}
  className={`status-box ${isSearching ? 'animate-fade-in' : ''}`}
>
  {statusText}
</div>
```

```css
/* CSSアニメーション定義 */
.animate-fade-in {
  animation: fadeIn 0.5s ease-in-out;
}
@keyframes fadeIn {
  0% { opacity: 0; }
  100% { opacity: 1; }
}
```

## モバイルUI対応（iOS Safari）

### ドロップダウンメニューはhoverではなくクリック/タップベースで実装

iOS Safariでは`:hover`がタップで正しく動作しない。CSS hover ベース（`group-hover`等）のドロップダウンは、スマホで開けない問題が発生する。

```tsx
// NG: CSS hoverベース（iOSで動作しない）
<div className="relative group">
  <button>メニュー ▼</button>
  <div className="opacity-0 invisible group-hover:opacity-100 group-hover:visible">
    <button>オプション1</button>
    <button>オプション2</button>
  </div>
</div>

// OK: useState + onClick ベース
function Dropdown() {
  const dropdownRef = useRef<HTMLDivElement>(null);
  const [isOpen, setIsOpen] = useState(false);

  // 外側タップで閉じる（touchstartも必須）
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent | TouchEvent) => {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target as Node)) {
        setIsOpen(false);
      }
    };

    if (isOpen) {
      document.addEventListener('mousedown', handleClickOutside);
      document.addEventListener('touchstart', handleClickOutside);  // iOS対応
    }
    return () => {
      document.removeEventListener('mousedown', handleClickOutside);
      document.removeEventListener('touchstart', handleClickOutside);
    };
  }, [isOpen]);

  return (
    <div className="relative" ref={dropdownRef}>
      <button onClick={() => setIsOpen(!isOpen)}>メニュー ▼</button>
      {isOpen && (
        <div className="absolute right-0 top-full mt-1 bg-white border rounded-lg shadow-lg z-10">
          <button
            onClick={() => { setIsOpen(false); handleOption1(); }}
            className="block w-full px-4 py-2 hover:bg-gray-100 active:bg-gray-200"
          >
            オプション1
          </button>
          <button
            onClick={() => { setIsOpen(false); handleOption2(); }}
            className="block w-full px-4 py-2 hover:bg-gray-100 active:bg-gray-200"
          >
            オプション2
          </button>
        </div>
      )}
    </div>
  );
}
```

**ポイント**:
- `mousedown` だけでなく `touchstart` も必要（iOS対応）
- `active:bg-gray-200` でタップ時のフィードバックを追加
- メニュー選択後は `setIsOpen(false)` で閉じる

## SSEストリーミング処理

### 基本パターン
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
      try {
        const event = JSON.parse(data);
        handleEvent(event);
      } catch {
        // JSONパースエラーは無視
      }
    }
  }
}
```

### イベントハンドリング
```typescript
function handleEvent(event) {
  // APIによってcontent/dataのどちらかにペイロードが入る
  const textValue = event.content || event.data;

  switch (event.type) {
    case 'text':
      onText(textValue);
      break;
    case 'tool_use':
      onToolUse(textValue);  // ツール名が返る
      break;
    case 'markdown':
      onMarkdown(textValue);
      break;
    case 'error':
      onError(new Error(event.error || event.message || textValue));
      break;
  }
}
```

### エラーハンドリング
```typescript
// ストリーミング中のエラー
case 'error':
  if (event.error || event.message) {
    callbacks.onError(new Error(event.error || event.message));
  }
  break;

// HTTPエラー
const response = await fetch(url, options);
if (!response.ok) {
  throw new Error(`API Error: ${response.status} ${response.statusText}`);
}
```

### アイドルタイムアウト（2段構成）

SSEストリームに2段階のタイムアウトを設定し、接続障害と推論ハングの両方を検知するパターン：

```typescript
async function readSSEStream(
  reader: ReadableStreamDefaultReader<Uint8Array>,
  onEvent: (event: Record<string, unknown>) => void,
  idleTimeoutMs?: number,          // 初回イベント受信前（短め: 10秒）
  ongoingIdleTimeoutMs?: number    // イベント間（長め: 60秒）
): Promise<void> {
  let firstEventReceived = false;

  while (true) {
    // フェーズに応じてタイムアウト値を切り替え
    const currentTimeout = firstEventReceived ? ongoingIdleTimeoutMs : idleTimeoutMs;
    if (currentTimeout) {
      const timeoutPromise = new Promise<never>((_, reject) => {
        setTimeout(() => reject(new SSEIdleTimeoutError(currentTimeout)), currentTimeout);
      });
      readResult = await Promise.race([reader.read(), timeoutPromise]);
    } else {
      readResult = await reader.read();
    }
    // ... イベント処理後に firstEventReceived = true
  }
}
```

| フェーズ | タイムアウト | 検知対象 |
|---------|------------|---------|
| 初回イベント受信前 | 短め（10秒） | スロットリング、接続エラー |
| イベント間（初回受信後） | 長め（60秒） | 推論ハング、モデル無応答 |

**設計ポイント**:
- 初回タイムアウトは短く → ユーザーを素早くエラーに気づかせる
- イベント間タイムアウトは長めに → 正常な推論やツール実行を妨げない
- 通常のストリーミングではチャンクが頻繁に来るため、60秒無音は異常と判断できる

### モック実装（ローカル開発用）

```typescript
export async function invokeAgentMock(prompt, callbacks) {
  const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));

  // 思考過程をストリーミング
  const thinkingText = `${prompt}について考えています...`;
  for (const char of thinkingText) {
    callbacks.onText(char);
    await sleep(20);
  }

  callbacks.onStatus('生成中...');
  await sleep(1000);

  callbacks.onMarkdown('# 生成結果\n\n...');
  callbacks.onComplete();
}

// 環境変数で切り替え
const useMock = import.meta.env.VITE_USE_MOCK === 'true';
const invoke = useMock ? invokeAgentMock : invokeAgent;
```

### PDF生成（Base64デコード・ダウンロード）

```typescript
export async function exportPdf(markdown: string): Promise<Blob> {
  const response = await fetch(url, {
    method: 'POST',
    headers: { /* 認証ヘッダー等 */ },
    body: JSON.stringify({ action: 'export_pdf', markdown }),
  });

  const reader = response.body?.getReader();
  const decoder = new TextDecoder();
  let buffer = '';

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split('\n');
    buffer = lines.pop() || '';

    for (const line of lines) {
      if (line.startsWith('data: ')) {
        const event = JSON.parse(line.slice(6));
        if (event.type === 'pdf' && event.data) {
          // Base64デコードしてBlobを返す
          const binaryString = atob(event.data);
          const bytes = new Uint8Array(binaryString.length);
          for (let i = 0; i < binaryString.length; i++) {
            bytes[i] = binaryString.charCodeAt(i);
          }
          return new Blob([bytes], { type: 'application/pdf' });
        }
      }
    }
  }
  throw new Error('PDF生成に失敗しました');
}

// ダウンロード処理
const blob = await exportPdf(markdown);
const url = URL.createObjectURL(blob);
const a = document.createElement('a');
a.href = url;
a.download = 'slide.pdf';
a.click();
URL.revokeObjectURL(url);
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

### 認証フローの変更（services prop）

Authenticatorのデフォルト認証フローを変更する場合、`services` propで `handleSignIn` をオーバーライドする。

```tsx
import { signIn } from 'aws-amplify/auth';

<Authenticator
  components={authComponents}
  services={{
    handleSignIn: (input) => signIn({
      ...input,
      options: { authFlowType: 'USER_PASSWORD_AUTH' }
    }),
  }}
>
```

**主なユースケース**: Cognito User Migration Trigger。Migration TriggerはパスワードがLambdaに平文で渡される `USER_PASSWORD_AUTH` フローでのみ発火する。デフォルトの `USER_SRP_AUTH` では発火しない。

| 認証フロー | パスワード | Migration Trigger |
|-----------|-----------|-------------------|
| `USER_SRP_AUTH`（デフォルト） | 暗号化して送信 | 発火しない |
| `USER_PASSWORD_AUTH` | 平文で送信 | 発火する |

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

### SSEストリーミング時の複数ツール発火対応

同一ツールの`onToolUse`が複数回発火する場合、**重複チェック + テキスト受信時の自動完了** の組み合わせで対処する。

```typescript
onToolUse: (toolName) => {
  if (toolName === 'web_search') {
    setMessages(prev => {
      // 進行中のステータスがあればスキップ（同一呼び出しの重複防止）
      const hasInProgress = prev.some(
        msg => msg.isStatus && msg.statusText === 'Web検索中...'
      );
      if (hasInProgress) return prev;
      return [
        ...prev,
        { role: 'assistant', content: '', isStatus: true, statusText: 'Web検索中...' }
      ];
    });
  }
},
onText: (text) => {
  stopTipRotation();  // スピナーのTIPSローテーションも停止
  setMessages(prev => {
    // テキスト受信時に全ての進行中ステータスを自動完了
    let msgs = prev.map(msg => {
      if (msg.isStatus && msg.statusText?.startsWith('Web検索中'))
        return { ...msg, statusText: 'Web検索完了' };
      if (msg.isStatus && msg.statusText?.startsWith('スライドを生成中'))
        return { ...msg, statusText: 'スライドを生成しました', tipIndex: undefined };
      return msg;
    });
    // 以降の処理はmsgsを使う（prevではなく）
    return [...msgs, { role: 'assistant', content: text }];
  });
}
```

**重要**: テキスト受信（`onText`）はツール完了のシグナルとして機能する。LLMのストリーミングでは、ツール実行完了後にLLMが次のテキスト応答を生成するため、`onText`が呼ばれた時点で全ての進行中ステータスを完了にするのが正しい。`onMarkdown` だけに頼ると、エージェント全体の完了まで待たされてスピナーが回り続ける。

**ポイント**: `prev`をmapした結果は新しい配列。後続処理ではmap結果の変数（`msgs`）を使うこと。`prev`を参照すると変更が反映されない。

## 疑似ストリーミング表示（1文字ずつ表示）

メッセージを1文字ずつ表示して、AIが入力しているような演出を作るパターン：

```typescript
const streamMessage = async (message: string) => {
  // 空のストリーミングメッセージを追加
  setMessages(prev => [...prev, { role: 'assistant', content: '', isStreaming: true }]);

  // 1文字ずつ追加
  for (const char of message) {
    await new Promise(resolve => setTimeout(resolve, 30));  // 30ms間隔
    setMessages(prev =>
      prev.map((msg, idx) =>
        idx === prev.length - 1 && msg.isStreaming
          ? { ...msg, content: msg.content + char }
          : msg
      )
    );
  }

  // ストリーミング完了
  setMessages(prev =>
    prev.map((msg, idx) =>
      idx === prev.length - 1 && msg.isStreaming
        ? { ...msg, isStreaming: false }
        : msg
    )
  );
};
```

**用途例**:
- エラーメッセージの表示
- 初期メッセージや案内文
- 編集プロンプトの表示

### finallyブロックとの競合に注意（カーソル表示の維持）

コールバック内で疑似ストリーミングを呼ぶ場合、`finally`ブロックとの競合に注意が必要：

```typescript
// ❌ 問題: finallyが先に実行され、isStreaming: false になりカーソルが消える
onError: (error) => {
  streamErrorMessage(displayMessage);  // awaitなしで呼ばれる
},
// ...
} finally {
  setMessages(prev =>
    prev.map(msg => msg.isStreaming ? { ...msg, isStreaming: false } : msg)
  );
}

// ✅ 解決策: 毎回 isStreaming: true を設定してカーソル表示を維持
for (const char of message) {
  await new Promise(resolve => setTimeout(resolve, 30));
  setMessages(prev =>
    prev.map((msg, idx) =>
      idx === prev.length - 1 && msg.role === 'assistant'
        ? { ...msg, content: msg.content + char, isStreaming: true }  // 毎回trueを設定
        : msg
    )
  );
}
```

**ポイント**: コールバック内の非同期関数は`await`されないため、`finally`ブロックが先に実行される。毎回`isStreaming: true`を設定することで、finallyで一度`false`になっても次の文字追加時に`true`に戻り、カーソル `▌` が表示され続ける。

## 非同期コールバック内でのエラーハンドリング

`invokeAgent`等の非同期関数に渡す`onError`コールバック内で`throw error`しても、外側の`try-catch`には**伝播しない**。コールバック内で直接状態を更新する必要がある：

```typescript
// ❌ NG: throw しても外側の catch に届かない
onError: (error) => {
  console.error('Error:', error);
  throw error;  // 外側の catch には届かない！
},

// ✅ OK: コールバック内で直接状態を更新
onError: (error) => {
  console.error('Error:', error);
  const errorMessage = error instanceof Error ? error.message : String(error);

  // 特定のエラーを判定してカスタムメッセージを表示
  const isModelNotAvailable = errorMessage.includes('model identifier is invalid');
  const displayMessage = isModelNotAvailable
    ? 'モデルがまだ利用できません。リリースをお待ちください！'
    : 'エラーが発生しました。もう一度お試しください。';

  // 疑似ストリーミングで表示（上記パターンを使用）
  streamErrorMessage(displayMessage);
  setIsLoading(false);
},
```

**理由**: `onError`は`invokeAgent`内部の`try-catch`で呼ばれるため、その中で`throw`してもinvokeAgentのPromiseは正常に解決される。

## 環境変数の読み込み（.env vs .env.local）

| フレームワーク/ツール | .env | .env.local | 備考 |
|-----------|------|-----------|------|
| Vite | ○ | ○ | 両方読む（優先度: .env.local > .env） |
| Next.js | ○ | ○ | 両方読む |
| **Node.js dotenv** | ○ | × | `.env` のみ |

Amplify CDK（`import 'dotenv/config'`）とViteの両方で使う場合は **`.env`** に統一する。

## OGP/Twitterカード設定

### 推奨設定（summaryカード）

Twitterで画像付きカードを表示するための完全な設定。`og:*` と `twitter:*` の両方を明示的に指定することが重要。

```html
<!-- OGP -->
<meta property="og:title" content="タイトル" />
<meta property="og:description" content="説明" />
<meta property="og:type" content="website" />
<meta property="og:url" content="https://example.com/" />
<meta property="og:image" content="https://example.com/ogp.jpg?v=2" />
<meta property="og:image:secure_url" content="https://example.com/ogp.jpg?v=2" />
<meta property="og:image:width" content="512" />
<meta property="og:image:height" content="512" />
<meta property="og:image:type" content="image/jpeg" />

<!-- Twitter Card -->
<meta name="twitter:card" content="summary" />
<meta name="twitter:site" content="@username" />
<meta name="twitter:title" content="タイトル" />
<meta name="twitter:description" content="説明" />
<meta name="twitter:image" content="https://example.com/ogp.jpg?v=2" />
```

### カード種類と画像サイズ

| カード種類 | 表示 | 推奨画像サイズ |
|-----------|------|---------------|
| `summary` | 小さい画像が右側 | 512x512（正方形） |
| `summary_large_image` | 大きい画像が上部 | 1200x630（横長） |

### 画像のExif削除

iPhoneで撮った画像などはExifメタデータが含まれている場合がある。削除推奨。

```python
from PIL import Image
img = Image.open('original.jpg')
img_clean = Image.new('RGB', img.size)
img_clean.paste(img)
img_clean.save('ogp.jpg', 'JPEG', quality=85)
```

### キャッシュ対策

画像URLにバージョンパラメータを追加してキャッシュを回避：
- `ogp.jpg?v=2` のようにクエリパラメータを追加
- 変更後は [Twitter Card Validator](https://cards-dev.twitter.com/validator) で再検証

## Tailwind CSS Tips

### リストの行頭記号（箇条書き）

Tailwind CSS v4のPreflight（CSSリセット）が`list-style: none`を適用するため、デフォルトで箇条書きの記号（•）が表示されない。

```tsx
// NG: 行頭記号が表示されない
<ul className="text-sm">
  <li>項目1</li>
  <li>項目2</li>
</ul>

// OK: list-disc list-inside を追加
<ul className="text-sm list-disc list-inside">
  <li>項目1</li>
  <li>項目2</li>
</ul>
```

| クラス | 効果 |
|--------|------|
| `list-disc` | 黒丸（•）を表示 |
| `list-decimal` | 番号（1. 2. 3.）を表示 |
| `list-inside` | 記号をテキスト内側に配置 |
| `list-outside` | 記号をテキスト外側に配置（デフォルト） |

### CSSショートハンドの !important 落とし穴

Tailwindリセット対策で `list-style: disc !important` のようにショートハンドを使うと、意図せず `list-style-position` 等のサブプロパティもリセットされる。個別プロパティ（`list-style-type`）で指定すること。

```css
/* NG */
.marpit ul { list-style: disc !important; }
/* OK */
.marpit ul { list-style-type: disc !important; }
```

詳細は `/kb-troubleshooting` の「CSSショートハンド: list-style が list-style-position を上書きする」を参照。

## モーダルの状態管理パターン

### 確認 → 処理中 → 結果表示の3段階モーダル

危険な操作（削除、公開など）は確認モーダルを挟むのがベストプラクティス。

```tsx
// 状態管理
const [showConfirm, setShowConfirm] = useState(false);  // 確認モーダル
const [isProcessing, setIsProcessing] = useState(false);  // 処理中フラグ
const [result, setResult] = useState<Result | null>(null);  // 結果（結果モーダル表示用）

// 確認モーダルを開く
const handleRequest = () => {
  setShowConfirm(true);
};

// 処理実行
const handleConfirm = async () => {
  setIsProcessing(true);
  try {
    const result = await doSomething();
    setShowConfirm(false);  // 確認モーダルを閉じる
    setResult(result);       // 結果モーダルを開く
  } catch (error) {
    setShowConfirm(false);
    alert(`エラー: ${error.message}`);
  } finally {
    setIsProcessing(false);
  }
};

// JSX
<ConfirmModal
  isOpen={showConfirm}
  onConfirm={handleConfirm}
  onCancel={() => setShowConfirm(false)}
  isProcessing={isProcessing}  // ボタンを「処理中...」に変更 + 無効化
/>
<ResultModal
  isOpen={!!result}
  result={result}
  onClose={() => setResult(null)}
/>
```

### 確認モーダルで「処理中」を表示するポイント

モーダルを閉じるのは**処理完了後**にする。閉じるのが先だと「処理中...」が見えない。

```tsx
// NG: 先にモーダルを閉じる → 「処理中...」が見えない
const handleConfirm = async () => {
  setShowConfirm(false);  // ← ここで閉じると
  setIsProcessing(true);  // ← この変更が見えない
  // ...処理...
};

// OK: 処理完了後にモーダルを閉じる
const handleConfirm = async () => {
  setIsProcessing(true);  // ボタンが「処理中...」に変わる
  try {
    const result = await doSomething();
    setShowConfirm(false);  // 処理完了後に閉じる
    setResult(result);
  } finally {
    setIsProcessing(false);
  }
};
```
