# Custom domains, AgentCore WebSocket, and errors

## 目次

- カスタムドメイン設定
  - Amplifyのドメイン所有権検証
  - 複数サブドメインが紐づくドメインの管理
  - カスタムドメイン設定の手順（CLIベース）
- AgentCore WebSocket 認証（ブラウザ接続）
  - JWT 認証は WebSocket に使えない
  - WebSocket 接続先 URL
  - IAM 権限設定
  - amplify_outputs.json の custom フィールド
  - SigV4 事前署名 URL の生成（ブラウザ側）
- よくあるエラー
  - amplify_outputs.json が見つからない
  - カスタム出力が反映されない
  - Runtime名バリデーションエラー
  - S3バケット名: アンダースコア不可
  - CDK DynamoDB: pointInTimeRecoverySpecification の型エラー
  - Amplify Console: SCP拒否エラー（Projectタグ必須環境）
  - Cognito Migration Trigger: Lambdaが発火しない
  - AgentCore S3バケット: grantRead だけでは書き込み不可

## カスタムドメイン設定

### Amplifyのドメイン所有権検証

Amplifyカスタムドメインを設定する際、サブドメインのDNSレコードは **CNAMEレコード** で設定する必要がある。

```bash
# NG: Aレコード（Alias）→ 所有権検証が通らない
aws route53 change-resource-record-sets --change-batch '{
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "myapp.example.com",
      "Type": "A",
      "AliasTarget": {
        "HostedZoneId": "Z2FDTNDATAQYW2",
        "DNSName": "dXXXXXX.cloudfront.net",
        "EvaluateTargetHealth": false
      }
    }
  }]
}'

# OK: CNAMEレコード → 即座に検証通過
aws route53 change-resource-record-sets --change-batch '{
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "myapp.example.com",
      "Type": "CNAME",
      "TTL": 300,
      "ResourceRecords": [{"Value": "dXXXXXX.cloudfront.net"}]
    }
  }]
}'
```

### 複数サブドメインが紐づくドメインの管理

1つのAmplifyアプリに複数のサブドメインが紐づいている場合:

```bash
# NG: delete-domain-association → 全サブドメインが消える
aws amplify delete-domain-association --domain-name example.com

# OK: update-domain-association → 残したいサブドメインだけ指定
aws amplify update-domain-association \
  --app-id <app-id> \
  --domain-name example.com \
  --sub-domain-settings prefix=keep-this,branchName=main
```

### カスタムドメイン設定の手順（CLIベース）

```bash
# 1. 新Amplifyにドメイン追加
aws amplify create-domain-association \
  --app-id <app-id> \
  --domain-name example.com \
  --sub-domain-settings prefix=myapp,branchName=main

# 2. 出力されたCNAMEレコードをRoute 53に設定
#    - SSL証明書検証用CNAME（_xxxx.example.com）
#    - サブドメインのCNAME（myapp.example.com → dXXXXXX.cloudfront.net）

# 3. ステータス確認（AVAILABLE になれば完了）
aws amplify get-domain-association \
  --app-id <app-id> \
  --domain-name example.com
```

ステータス遷移: `CREATING` → `PENDING_VERIFICATION` → `PENDING_DEPLOYMENT` → `AVAILABLE`

---

## AgentCore WebSocket 認証（ブラウザ接続）

### JWT 認証は WebSocket に使えない

`RuntimeAuthorizerConfiguration.usingJWT()` で設定した JWT 認証は HTTP invocations 専用。ブラウザの WebSocket API はカスタムヘッダーを設定できないため、Bearer トークンを渡せない。

**解決策**: JWT 認証を削除し、**IAM (SigV4) 認証** + Cognito Identity Pool に変更。

### WebSocket 接続先 URL

```
wss://bedrock-agentcore.{region}.amazonaws.com/runtimes/{runtimeArn}/ws?qualifier=DEFAULT
```

- ARN は**エンコードしない**（公式サンプル準拠）
- `qualifier=DEFAULT` は**必須**

### IAM 権限設定

Cognito 認証済みロールに WebSocket 用の権限を付与：

```typescript
import * as iam from 'aws-cdk-lib/aws-iam';

// Cognito Identity Pool の認証済みロールに付与
const authenticatedRole = backend.auth.resources.authenticatedUserIamRole;

authenticatedRole.addToPrincipalPolicy(new iam.PolicyStatement({
  actions: ['bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStream'],
  resources: [
    runtime.agentRuntimeArn,        // Runtime ARN 本体
    `${runtime.agentRuntimeArn}/*`, // サブリソース
  ],
}));
```

**注意点**:
- アクション名は `bedrock-agentcore:InvokeAgentRuntimeWithWebSocketStream`（`bedrock-agentcore:*` では不十分な場合あり）
- リソースは Runtime ARN そのもの + ワイルドカード（`/runtime-endpoint/DEFAULT` 等のサブリソースもカバー）

### amplify_outputs.json の custom フィールド

`Amplify.getConfig()` は `custom` フィールドを返さない。カスタム出力（Runtime ARN、リージョン等）にアクセスするには `amplify_outputs.json` を直接 import する。

```typescript
// NG: custom が取れない
const config = Amplify.getConfig();
const arn = config.custom?.runtimeArn; // undefined

// OK: 直接 import
import outputs from '../amplify_outputs.json';
const arn = outputs.custom?.runtimeArn;
```

### SigV4 事前署名 URL の生成（ブラウザ側）

```typescript
import { SignatureV4 } from '@smithy/signature-v4';
import { HttpRequest } from '@smithy/protocol-http';
import { Sha256 } from '@aws-crypto/sha256-js';

const signer = new SignatureV4({
  service: 'bedrock-agentcore', region,
  credentials, // Cognito Identity Pool の IAM 認証情報
  sha256: Sha256,
});

const request = new HttpRequest({
  method: 'GET', protocol: 'https:',
  hostname: `bedrock-agentcore.${region}.amazonaws.com`,
  path: `/runtimes/${runtimeArn}/ws`,
  query: { qualifier: 'DEFAULT' },
  headers: { host: `bedrock-agentcore.${region}.amazonaws.com` },
});

const presigned = await signer.presign(request, { expiresIn: 300 });
```

---

## よくあるエラー

### amplify_outputs.json が見つからない
- sandbox が起動していない
- `npx ampx sandbox` を実行する

### カスタム出力が反映されない
- `backend.addOutput()` を追加後、sandbox再起動が必要

### Runtime名バリデーションエラー

**症状**: `[ValidationError] Runtime name must start with a letter and contain only letters, numbers, and underscores`

**原因**: sandbox識別子（デフォルトでユーザー名）にハイフン等の禁止文字が含まれている（例: `my-name`）

**解決策**: `backend.ts`でRuntime名をサニタイズ
```typescript
const backendName = agentCoreStack.node.tryGetContext('amplify-backend-name') as string;
nameSuffix = (backendName || 'dev').replace(/[^a-zA-Z0-9_]/g, '_');
```

### S3バケット名: アンダースコア不可

**症状**: `[ValidationError] Invalid S3 bucket name`（アンダースコア含む名前）

**解決策**: バケット名生成時にアンダースコアをハイフンに変換
```typescript
const sanitizedSuffix = nameSuffix.replace(/_/g, '-').toLowerCase();
```

S3命名規則: 小文字(a-z)、数字(0-9)、ハイフン(`-`)、ピリオド(`.`)のみ。アンダースコア不可。

### CDK DynamoDB: pointInTimeRecoverySpecification の型エラー

**症状**: `Type 'boolean' is not assignable to type 'PointInTimeRecoverySpecification'`

**原因**: aws-cdk-lib の最新版で型が `boolean` からオブジェクト型に変更

**解決策**: PITRが不要ならプロパティ自体を削除（デフォルトで無効）

### Amplify Console: SCP拒否エラー（Projectタグ必須環境）

**症状**: `lambda:CreateFunction ... with an explicit deny in a service control policy`

**原因**: スタック単位のタグはAmplify自動生成リソースに付かない

**解決策**: **CDK Appレベル**でタグを付与
```typescript
const app = cdk.App.of(agentCoreStack);
if (app) {
  cdk.Tags.of(app).add('Project', '<プロジェクトタグ>');
}
```

### Cognito Migration Trigger: Lambdaが発火しない

**症状**: Migration Lambda設定済みだが、サインイン時に発火しない

**原因**: Amplify UIの`<Authenticator>`はデフォルトで`USER_SRP_AUTH`。SRPではMigration Triggerにパスワードが渡されない

**解決策**: `services` propで`USER_PASSWORD_AUTH`を使用（移行完了後は戻すこと）
```tsx
<Authenticator services={{
  handleSignIn: (input) => signIn({...input, options: { authFlowType: 'USER_PASSWORD_AUTH' }}),
}}>
```

### AgentCore S3バケット: grantRead だけでは書き込み不可

**症状**: S3アップロードで「AccessDenied」

**解決策**: `bucket.grantReadWrite(runtime)` を使用（`grantRead` では書き込み不可）
