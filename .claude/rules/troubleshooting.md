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

### Amplify Console: CDK failed to publish assets

**症状**: `[CDKAssetPublishError] CDK failed to publish assets`

**原因**: サービスロールの権限不足（デフォルトで作成される`AmplifySSRLoggingRole`はロギング専用）

**解決策**: 適切な権限を持つサービスロールを作成・設定

```bash
# 1. サービスロールを作成
aws iam create-role \
  --role-name AmplifyServiceRole-myapp \
  --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {"Service": "amplify.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }]
  }'

# 2. AdministratorAccess-Amplifyポリシーをアタッチ
aws iam attach-role-policy \
  --role-name AmplifyServiceRole-myapp \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess-Amplify

# 3. Amplifyアプリに設定
aws amplify update-app \
  --app-id YOUR_APP_ID \
  --iam-service-role-arn arn:aws:iam::ACCOUNT_ID:role/AmplifyServiceRole-myapp
```

### Amplify Console: Dockerビルドができない

**症状**: `Unable to execute 'docker' in order to build a container asset`

**原因**: デフォルトビルドイメージにDockerが含まれていない

**解決策**: カスタムビルドイメージを設定

1. Amplify Console → Build settings → Build image settings → Edit
2. Build image → Custom Build Image を選択
3. イメージ名: `public.ecr.aws/codebuild/amazonlinux-x86_64-standard:5.0`

## フロントエンド関連

### OGP/Twitterカード: 画像が表示されない

**症状**: TwitterでURLをシェアしてもカード画像が表示されない

**原因候補**:
1. `og:image`が相対パス（`/image.jpg`）になっている → Twitterは絶対URLが必須
2. `twitter:image`タグがない
3. 画像サイズが大きすぎる（5MB超）
4. HTTPS未対応

**解決策**:
```html
<!-- OGP -->
<meta property="og:url" content="https://example.com/" />
<meta property="og:image" content="https://example.com/ogp.jpg" />

<!-- Twitter Card -->
<meta name="twitter:card" content="summary_large_image" />
<meta name="twitter:image" content="https://example.com/ogp.jpg" />
```

**チェックリスト**:
- [ ] `og:image`と`twitter:image`は絶対URL（`https://`から始まる）
- [ ] `og:url`でサイトURLを明示
- [ ] 画像は5MB以下、推奨1200×630px
- [ ] `twitter:card`は`summary`（小）か`summary_large_image`（大）
- [ ] HTTPSで配信されている

**注意**: Twitterカードのキャッシュは最大7日間保持される。修正後すぐに反映されない場合がある。

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

### Marp CLI: PDF日本語文字化け（豆腐文字）

**症状**: PDFをダウンロードすると日本語が□（豆腐）で表示される

**原因**: Dockerコンテナに日本語フォントがない

**解決策**: Dockerfileに日本語フォントを追加
```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    chromium \
    fonts-noto-cjk \
    && rm -rf /var/lib/apt/lists/* \
    && fc-cache -fv
```

**補足**: `fonts-noto-cjk`はNoto Sans CJK（中国語・日本語・韓国語）フォントを含む

## LLMアプリ関連

### ストリーミング中のコードブロック除去が困難

**症状**: LLMがマークダウンをテキストとして出力すると、チャンク単位で```の検出が難しい

**原因**: SSEイベントはチャンク単位で来るため、```markdown と閉じの ``` が別チャンクになる

**解決策**: 出力専用のツールを作成し、ツール経由で出力させる
```python
@tool
def output_content(content: str) -> str:
    """生成したコンテンツを出力します。"""
    global _generated_content
    _generated_content = content
    return "出力完了"
```

システムプロンプトで「必ずこのツールを使って出力してください」と指示する。

### Tavily APIキーの環境変数

**症状**: AgentCore RuntimeでTavily検索が動かない

**原因**: 環境変数がランタイムに渡されていない

**解決策**: CDKで環境変数を設定
```typescript
const runtime = new agentcore.Runtime(stack, 'MyRuntime', {
  runtimeName: 'my-agent',
  agentRuntimeArtifact: artifact,
  environmentVariables: {
    TAVILY_API_KEY: process.env.TAVILY_API_KEY || '',
  },
});
```

sandbox起動時に環境変数を設定:
```bash
export TAVILY_API_KEY=$(grep TAVILY_API_KEY .env | cut -d= -f2) && npx ampx sandbox
```

## Amplify sandbox関連

### 複数sandboxインスタンス競合

**症状**:
```
[ERROR] [MultipleSandboxInstancesError] Multiple sandbox instances detected.
```

**原因**: 複数のampxプロセスが同時実行中

**解決策**:
```bash
# 1. プロセス確認
ps aux | grep "ampx" | grep -v grep

# 2. アーティファクトクリア
rm -rf .amplify/artifacts/

# 3. sandbox完全削除（正しい方法）
npx ampx sandbox delete --yes

# 4. 新しくsandbox起動
npx ampx sandbox
```

**注意**: `pkill` や `kill` でプロセスを強制終了すると状態が不整合になる。必ず `sandbox delete` を使う。

### sandbox変更が反映されない

**症状**: agent.pyを変更してもランタイムに反映されない

**原因候補**:
1. 複数sandboxインスタンスの競合
2. Docker未起動
3. Hotswapが正しく動作していない

**解決策**:
1. sandbox deleteで完全削除
2. Dockerが起動していることを確認
3. 新しくsandbox起動
4. デプロイ完了を待つ（5-10分）

### Docker未起動エラー

**症状**:
```
ERROR: Cannot connect to the Docker daemon
[ERROR] [UnknownFault] ToolkitError: Failed to build asset
```

**解決策**: Docker Desktop起動後、ファイルをtouchして再トリガー

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

### Marpテーマ確認

スライドに適用されているテーマを確認するには、ブラウザDevToolsで:
```javascript
// section要素のdata-theme属性を確認
document.querySelectorAll('section[data-theme]')
```
