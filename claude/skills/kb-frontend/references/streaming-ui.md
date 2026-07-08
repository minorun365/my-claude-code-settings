# ストリーミングUI表示

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

### フェードインアニメーションの発火（keyを変える）

```tsx
<div
  key={isSearching ? `search-${statusText}` : index}
  className={`status-box ${isSearching ? 'animate-fade-in' : ''}`}
>
  {statusText}
</div>
```

## 疑似ストリーミング表示（1文字ずつ表示）

```typescript
const streamMessage = async (message: string) => {
  setMessages(prev => [...prev, { role: 'assistant', content: '', isStreaming: true }]);

  for (const char of message) {
    await new Promise(resolve => setTimeout(resolve, 30));
    setMessages(prev =>
      prev.map((msg, idx) =>
        idx === prev.length - 1 && msg.isStreaming
          ? { ...msg, content: msg.content + char }
          : msg
      )
    );
  }

  setMessages(prev =>
    prev.map((msg, idx) =>
      idx === prev.length - 1 && msg.isStreaming
        ? { ...msg, isStreaming: false }
        : msg
    )
  );
};
```

### finallyブロックとの競合に注意

コールバック内で疑似ストリーミングを呼ぶ場合、毎回 `isStreaming: true` を設定してカーソル表示を維持する：

```typescript
// ✅ 毎回 isStreaming: true を設定
for (const char of message) {
  await new Promise(resolve => setTimeout(resolve, 30));
  setMessages(prev =>
    prev.map((msg, idx) =>
      idx === prev.length - 1 && msg.role === 'assistant'
        ? { ...msg, content: msg.content + char, isStreaming: true }
        : msg
    )
  );
}
```

