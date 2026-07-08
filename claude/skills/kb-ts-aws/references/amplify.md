# Amplify sandbox / Console

## Amplify sandbox: amplify_outputs.json が見つからない

**症状**: `Cannot find module '../amplify_outputs.json'`

**原因**: sandbox が起動していない

**解決策**: `npx ampx sandbox` を実行

## Amplify Console: CDK failed to publish assets

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

## Amplify Console: Dockerビルドができない / CDKAssetPublishError

**症状パターン**:

| パターン | エラーメッセージ |
|---------|----------------|
| Docker 未搭載 | `Unable to execute 'docker' in order to build a container asset` |
| Docker 未搭載（抽象的） | `[CDKAssetPublishError] CDK failed to publish assets` |
| Docker Hub レートリミット | `429 Too Many Requests: You have reached your unauthenticated pull rate limit` |

**重要**: `CDKAssetPublishError` は Docker 未搭載が原因でも出る。`--debug` フラグなしでは真の原因が見えないことがある。

```yaml
# デバッグ: amplify.yml で --debug を付ける
- npx ampx pipeline-deploy --branch $AWS_BRANCH --app-id $AWS_APP_ID --debug
```

**解決策**:

1. **推奨: `deploy-time-build` を使って CodeBuild に Docker ビルドを委譲する**
   - Amplify のビルドイメージを変更する必要がない
   - `/kb-amplify-cdk` の `deploy-time-build` セクションを参照

2. **代替: カスタムビルドイメージを設定**
   - Amplify Console → Build settings → Build image settings → Edit
   - Build image → Custom Build Image を選択
   - イメージ名: `public.ecr.aws/codebuild/amazonlinux-x86_64-standard:5.0`

3. **Docker Hub レートリミット対策: Dockerfile のベースイメージを ECR Public に変更**
   ```dockerfile
   # NG: Docker Hub → 429 Too Many Requests
   FROM python:3.13-slim
   # OK: ECR Public → レートリミットなし
   FROM public.ecr.aws/docker/library/python:3.13-slim-bookworm
   ```

