# モバイルUI・ステータス表示・モーダル

## モバイルUI対応（iOS Safari）

### ドロップダウンメニューはhoverではなくクリック/タップベースで実装

iOS Safariでは`:hover`がタップで正しく動作しない。

```tsx
// NG: CSS hoverベース（iOSで動作しない）
<div className="relative group">
  <button>メニュー ▼</button>
  <div className="opacity-0 invisible group-hover:opacity-100 group-hover:visible">...</div>
</div>

// OK: useState + onClick ベース
function Dropdown() {
  const dropdownRef = useRef<HTMLDivElement>(null);
  const [isOpen, setIsOpen] = useState(false);

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
          <button onClick={() => { setIsOpen(false); handleOption1(); }}
            className="block w-full px-4 py-2 hover:bg-gray-100 active:bg-gray-200">
            オプション1
          </button>
        </div>
      )}
    </div>
  );
}
```

## ステータス表示パターン

### 重複防止（ツール使用イベント）

```typescript
onToolUse: (toolName) => {
  if (toolName === 'output_slide') {
    setMessages(prev => {
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

### ステータス遷移の連動

前のステータスを完了に更新しつつ、新しいステータスを追加する：

```typescript
if (toolName === 'output_slide') {
  setMessages(prev => {
    const updated = prev.map(msg =>
      msg.isStatus && msg.statusText === 'Web検索中...'
        ? { ...msg, statusText: 'Web検索完了' }
        : msg
    );
    return [
      ...updated,
      { role: 'assistant', content: '', isStatus: true, statusText: 'スライドを生成中...' }
    ];
  });
}
```

### SSEストリーミング時の複数ツール発火対応

```typescript
onText: (text) => {
  stopTipRotation();
  setMessages(prev => {
    // テキスト受信時に全ての進行中ステータスを自動完了
    let msgs = prev.map(msg => {
      if (msg.isStatus && msg.statusText?.startsWith('Web検索中'))
        return { ...msg, statusText: 'Web検索完了' };
      if (msg.isStatus && msg.statusText?.startsWith('スライドを生成中'))
        return { ...msg, statusText: 'スライドを生成しました', tipIndex: undefined };
      return msg;
    });
    return [...msgs, { role: 'assistant', content: text }];
  });
}
```

**重要**: テキスト受信（`onText`）はツール完了のシグナルとして機能する。`prev`をmapした結果は新しい配列。後続処理ではmap結果の変数（`msgs`）を使うこと。

## モーダルの状態管理パターン

### 確認 → 処理中 → 結果表示の3段階モーダル

```tsx
const [showConfirm, setShowConfirm] = useState(false);
const [isProcessing, setIsProcessing] = useState(false);
const [result, setResult] = useState<Result | null>(null);

const handleConfirm = async () => {
  setIsProcessing(true);
  try {
    const result = await doSomething();
    setShowConfirm(false);  // 処理完了後に閉じる
    setResult(result);
  } catch (error) {
    setShowConfirm(false);
    alert(`エラー: ${error.message}`);
  } finally {
    setIsProcessing(false);
  }
};
```

**ポイント**: モーダルを閉じるのは処理完了後。閉じるのが先だと「処理中...」が見えない。

