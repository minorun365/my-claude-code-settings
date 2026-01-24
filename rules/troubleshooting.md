# トラブルシューティング集

プロジェクト横断で遭遇した問題と解決策を記録する。

## AWS関連

### Cognito認証: client_id mismatch

**症状**: `Claim 'client_id' value mismatch with configuration.`

**原因**: IDトークンを使用していたが、APIがアクセストークンの`client_id`クレームを検証していた

**解決策**: アクセストークンを使用する
```typescript
// NG
const idToken = session.tokens?.idToken?.toString();

// OK
const accessToken = session.tokens?.accessToken?.toString();
```

### Bedrock: AccessDeniedException on inference-profile

**症状**: `AccessDeniedException: bedrock:InvokeModelWithResponseStream on resource: arn:aws:bedrock:*:*:inference-profile/*`

**原因**: クロスリージョン推論（`us.anthropic.claude-*`形式）を使用する際、IAM権限が不足

**解決策**: IAMポリシーに`inference-profile/*`を追加
```typescript
resources: [
  'arn:aws:bedrock:*::foundation-model/*',
  'arn:aws:bedrock:*:*:inference-profile/*',  // 追加
]
```

### Amplify sandbox: amplify_outputs.json が見つからない

**症状**: `Cannot find module '../amplify_outputs.json'`

**原因**: sandbox が起動していない

**解決策**: `npx ampx sandbox` を実行

## フロントエンド関連

### React StrictMode: 文字がダブって表示される

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

### Tailwind × Marp: invert クラスの競合

**症状**: Marpのダークテーマ（`class: invert`）が正しく表示されない

**原因**: Tailwind CSSの`.invert`ユーティリティ（`filter: invert(100%)`）が適用される

**解決策**: CSSで上書き
```css
.marpit section.invert {
  filter: none !important;
}
```

### Marp Core: スライドのCSSが適用されない

**症状**: スライドのスタイルが正しく表示されない

**原因**: `section`要素だけを抽出してDOM構造が崩れた

**解決策**: SVG要素をそのまま使い、`div.marpit`でラップする
```tsx
<div className="marpit">
  <div dangerouslySetInnerHTML={{ __html: svg.outerHTML }} />
</div>
```

### SSE: チャットの吹き出しが空のまま

**症状**: APIは成功（200）だが、UIに内容が表示されない

**原因**: APIは`event.data`を返すが、コードは`event.content`を期待していた

**解決策**: 両方に対応
```typescript
const textValue = event.content || event.data;
```

## Python関連

### uv: AWS認証エラー

**症状**: `aws login`で認証したのにBoto3でエラー

**原因**: `botocore[crt]`が不足

**解決策**:
```bash
uv add 'botocore[crt]'
```

### Marp CLI: PDF出力でエラー

**症状**: Dockerコンテナ内でPDF生成に失敗

**原因**: Chromiumがインストールされていない

**解決策**: Dockerfileに追加
```dockerfile
RUN apt-get update && apt-get install -y chromium
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
```

## デバッグTips

### Chrome DevTools MCP

ブラウザの問題を調査する際は、Chrome DevTools MCPを使用：
1. `list_console_messages` - コンソールエラー確認
2. `list_network_requests` - API呼び出し確認
3. `get_network_request` - リクエスト/レスポンス詳細確認

### CloudWatch Logs

Lambda/AgentCoreの問題を調査する際は、AWS CLIでログを確認：
```bash
aws logs tail /aws/bedrock-agentcore/runtime/RUNTIME_NAME --follow
```
