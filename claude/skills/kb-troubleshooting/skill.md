---
name: kb-troubleshooting
description: トラブルシューティング集。AWS/フロントエンド/Python/LLMアプリの問題解決
user-invocable: true
---

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

### AgentCore Observability: トレースが出力されない

**症状**: AgentCore Observability ダッシュボードでメトリクスが全て0、トレースが表示されない

**原因**: CDKでデプロイする場合、以下の3つすべてが必要（1つでも欠けるとトレースが出ない）

**解決策チェックリスト**:

1. **requirements.txt**
   - [x] `strands-agents[otel]` が含まれている（`strands-agents` だけではNG）
   - [x] `aws-opentelemetry-distro` が含まれている

2. **Dockerfile**
   - [x] CMD が `opentelemetry-instrument python agent.py` になっている
   - `python agent.py` だけではOTELが有効にならない
   ```dockerfile
   CMD ["opentelemetry-instrument", "python", "agent.py"]
   ```

3. **CDK環境変数**（CDKデプロイの場合）
   - [x] 以下の環境変数を設定
   ```typescript
   environmentVariables: {
     AGENT_OBSERVABILITY_ENABLED: 'true',
     OTEL_PYTHON_DISTRO: 'aws_distro',
     OTEL_PYTHON_CONFIGURATOR: 'aws_configurator',
     OTEL_EXPORTER_OTLP_PROTOCOL: 'http/protobuf',
   }
   ```

4. **CloudWatch Transaction Search**（アカウントごとに1回）
   ```bash
   # 状態確認
   aws xray get-trace-segment-destination --region us-east-1
   # Destination: CloudWatchLogs, Status: ACTIVE であること
   ```

5. **ログポリシー**（アカウントごとに1回）
   ```bash
   aws logs describe-resource-policies --region us-east-1
   # TransactionSearchXRayAccess ポリシーが存在すること
   ```

**重要**: 1〜3はすべて必須。1つでも欠けるとトレースが出力されない。

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

**原因**: 複数の設定が組み合わさって問題が発生。以下をすべて満たす必要がある。

**解決策チェックリスト**:

1. **metaタグ（必須）**
   - [x] `og:image` は絶対URL（`https://`から始まる）
   - [x] `og:url` でサイトURLを明示
   - [x] `og:image:secure_url` を追加
   - [x] `og:image:width` / `og:image:height` を追加
   - [x] `og:image:type` を追加（`image/jpeg` など）

2. **Twitter専用タグ（必須）**
   - [x] `twitter:card` は `summary`（小）か `summary_large_image`（大）
   - [x] `twitter:image` を明示的に指定
   - [x] `twitter:title` を明示的に指定
   - [x] `twitter:description` を明示的に指定

3. **画像ファイル**
   - [x] 5MB以下
   - [x] `summary` なら正方形（512x512推奨）
   - [x] `summary_large_image` なら横長（1200x630推奨）
   - [x] Exifメタデータを削除（iPhoneで撮った画像は要注意）
   - [x] HTTPSで配信されている

4. **キャッシュ対策**
   - [x] 画像URLにバージョンパラメータ追加（`?v=2` など）
   - [x] [Twitter Card Validator](https://cards-dev.twitter.com/validator) で再検証

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

### Marp Core: iOS Safari/Chromeでスライドが見切れる

**症状**: スマホ実機（iOS Safari/Chrome）でスライドプレビューが画面幅に収まらず見切れる。Chrome DevToolsのエミュレーションでは再現しない。

**原因**: WebKit Bug 23113（15年以上放置されているバグ）
- SVGの`<foreignObject>`内のHTMLがviewBox変換を正しく継承しない
- iOS上のすべてのブラウザはWebKitエンジンを使うため、Chromeでも発生

**解決策**: Marp公式の`marpit-svg-polyfill`を使用

```bash
npm install @marp-team/marpit-svg-polyfill
```

```tsx
import { useEffect, useRef } from 'react';
import { observe } from '@marp-team/marpit-svg-polyfill';

function SlidePreview({ markdown }) {
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (containerRef.current) {
      const cleanup = observe(containerRef.current);
      return cleanup;
    }
  }, [markdown]);

  return (
    <div ref={containerRef}>
      {/* Marpスライドを表示 */}
    </div>
  );
}
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

### Marp CLI: 複数出力形式でテーマ設定が一部だけ反映される

**症状**: PDF出力では正しいテーマが適用されるが、PPTX出力では常に同じテーマが使われる（環境ごとの切り替えが効かない）

**原因**: 出力形式ごとに別関数を作成した際、一方の関数でテーマをハードコードしていた

```python
# NG: PDF関数は環境変数参照、PPTX関数はハードコード
def generate_pdf(markdown: str) -> bytes:
    theme_path = Path(__file__).parent / f"{THEME_NAME}.css"  # ✅ 環境変数
    ...

def generate_pptx(markdown: str) -> bytes:
    theme_path = Path(__file__).parent / "border.css"  # ❌ ハードコード
    ...
```

**解決策**: すべての出力関数で環境変数を一貫して使用する

```python
# OK: 両関数とも環境変数から取得
THEME_NAME = os.environ.get("MARP_THEME", "border")  # デフォルトはborder

def generate_pdf(markdown: str) -> bytes:
    theme_path = Path(__file__).parent / f"{THEME_NAME}.css"
    ...

def generate_pptx(markdown: str) -> bytes:
    theme_path = Path(__file__).parent / f"{THEME_NAME}.css"  # 同じ方式に統一
    ...
```

**教訓**: 複数の出力形式を提供する場合、設定（テーマ、オプション等）の取得方法は**すべての関数で統一**する。コピペで関数を追加した際に、元の設定方法を変更し忘れるミスが起きやすい。

## SNS連携関連

### Twitter/Xシェア: ツイートボックスにテキストが入力されない

**症状**: シェアリンクをクリックしてTwitterを開いても、ツイートボックスにテキストが何も入力されていない

**原因**: `https://x.com/compose/post?text=...` 形式を使用していた。この形式はXのWeb UI直接アクセス用で、`text`パラメータが無視されることがある

**解決策**: Twitter Web Intent形式を使用する

```python
# NG: compose/post形式（textパラメータが無視される）
url = f"https://x.com/compose/post?text={encoded_text}"

# OK: Web Intent形式（textパラメータが確実に反映される）
url = f"https://twitter.com/intent/tweet?text={encoded_text}"
```

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

### Tavily APIレートリミット: フォールバックが効かない

**症状**: 複数APIキーのフォールバックを実装したが、枯渇したキーで止まり次のキーに切り替わらない

**原因**: Tavilyのエラーメッセージが `"This request exceeds your plan's set usage limit"` で、`rate limit` や `quota` という文字列を含まない

**解決策**: エラー判定条件に `"usage limit"` を追加
```python
if "rate limit" in error_str or "429" in error_str or "quota" in error_str or "usage limit" in error_str:
    continue  # 次のキーで再試行
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

### Tailwind: レスポンシブクラス変更がPC表示に反映されない

**症状**: `text-[8px]` に変更しても、PC画面で文字サイズが変わらない

**原因**: `md:text-xs` などのレスポンシブクラスがPC表示で優先されるため、ベースクラスの変更だけでは反映されない

**解決策**: ベースクラスとレスポンシブクラスの両方を変更する
```tsx
// NG: ベースのみ変更 → PCではmd:text-xsが適用される
className="text-[8px] md:text-xs"

// OK: 両方変更
className="text-[8px] md:text-[10px]"
```

### dotenv: .env.local が読み込まれない

**症状**: `.env.local`に環境変数を設定したが、Node.js（Amplify CDK等）で読み込まれない

**原因**: `dotenv`パッケージはデフォルトで`.env`のみ読む。`.env.local`はVite/Next.jsの独自サポート

**解決策**: `.env.local` → `.env` にリネーム（Viteは`.env`も読むため互換性あり）

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

### CloudWatch Logs Insights: タイムゾーン変換で時刻がズレる

**症状**: `datefloor(@timestamp + 9h, 1h)` でJSTに変換しているのに、結果の時刻がおかしい（古い時刻が返る）

**原因**: CloudWatch Logs Insightsの `datefloor(@timestamp + 9h, ...)` は挙動が不安定

**解決策**: UTCのまま集計してから、スクリプト側でJSTに変換する

```bash
# クエリはUTCで集計
--query-string 'stats count(*) by datefloor(@timestamp, 1h) as hour_utc | sort hour_utc asc'

# 結果をスクリプト側でJSTに変換
JST_HOUR=$(( (10#$UTC_HOUR + 9) % 24 ))
```

### AgentCore: OTELログ形式でinvocationがカウントできない

**症状**: `filter @message like /invocations/` でログをカウントしているが、件数が0になる

**原因**: OTEL有効時、ログ形式がJSON（OTEL形式）に変わり、従来のパターンマッチが効かない

**解決策**: `session.id` をparseしてユニークカウントする

```
# 旧方式（OTELログでは効かない）
filter @message like /invocations/ or @message like /POST/

# 新方式（OTEL対応）
parse @message /"session\.id":\s*"(?<sid>[^"]+)"/
| filter ispresent(sid)
| stats count_distinct(sid) as sessions
```

### Marpテーマ確認

スライドに適用されているテーマを確認するには、ブラウザDevToolsで:
```javascript
// section要素のdata-theme属性を確認
document.querySelectorAll('section[data-theme]')
```
