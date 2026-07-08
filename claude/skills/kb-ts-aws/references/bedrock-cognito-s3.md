# Cognito / Bedrock / S3 Vectors

## Cognito認証: client_id mismatch

**症状**: `Claim 'client_id' value mismatch with configuration.`

**原因**: IDトークンを使用していたが、APIがアクセストークンの`client_id`クレームを検証していた

**解決策**: アクセストークンを使用する
```typescript
// NG
const idToken = session.tokens?.idToken?.toString();

// OK
const accessToken = session.tokens?.accessToken?.toString();
```

## Bedrock Model Detector: 重複通知メール

**症状**: 新モデルリリース時に同じモデルの通知メールが複数回届く

**原因**: DynamoDBの「上書き保存」方式 + リリース直後のAPI不安定性の組み合わせ

1. T=0: APIに新モデル出現 → 検出・通知 → DynamoDBに保存
2. T=5: APIから一時的にモデルが消失 → DynamoDBをモデルなしで上書き
3. T=10: APIに再出現 → 再び「新モデル」として検出 → 重複通知

**解決策**: DynamoDBの保存を和集合（union）方式に変更。一度検出されたモデルはDBから消えないようにする

```python
# NG: APIの応答でそのまま上書き（モデルが消えるとDBからも消える）
save_models(region, current_models)

# OK: 前回のデータとの和集合で保存（一度検出されたモデルは残る）
save_models(region, current_models | previous_models)
```

**教訓**: 定期ポーリング型の差分検知では、外部APIの一時的な不安定性を考慮し、累積方式でデータを保持する。

## Bedrock: AccessDeniedException on inference-profile

**症状**: `AccessDeniedException: bedrock:InvokeModelWithResponseStream on resource: arn:aws:bedrock:*:*:inference-profile/*`

**原因**: クロスリージョン推論（`us.anthropic.claude-*`形式）を使用する際、IAM権限が不足

**解決策**: IAMポリシーに`inference-profile/*`を追加
```typescript
resources: [
  'arn:aws:bedrock:*::foundation-model/*',
  'arn:aws:bedrock:*:*:inference-profile/*',  // 追加
]
```

## S3 Vectors: Filterable metadata must have at most 2048 bytes

**症状**: Knowledge BaseのSync時にエラー `Filterable metadata must have at most 2048 bytes`

**原因**: S3 Vectorsではデフォルトで全メタデータがFilterable（2KB上限）扱い。

| メタデータタイプ | 上限 |
|-----------------|------|
| Filterable（フィルタリング可能） | **2KB** |
| Non-filterable（フィルタリング不可） | 40KB |

**解決策**: VectorIndex作成時に`MetadataConfiguration.NonFilterableMetadataKeys`を設定

```typescript
const vectorIndex = new CfnResource(stack, 'VectorIndex', {
  type: 'AWS::S3Vectors::Index',
  properties: {
    VectorBucketName: 'my-vectors-bucket',
    IndexName: 'my-index-v2',
    DataType: 'float32',
    Dimension: 1024,
    DistanceMetric: 'cosine',
    MetadataConfiguration: {
      NonFilterableMetadataKeys: [
        'AMAZON_BEDROCK_TEXT',
        'AMAZON_BEDROCK_METADATA',
      ],
    },
  },
});
```

**注意**: `MetadataConfiguration`の変更はReplacement（リソース再作成）を伴う。

