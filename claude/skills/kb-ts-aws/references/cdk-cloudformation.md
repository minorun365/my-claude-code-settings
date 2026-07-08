# CloudFormation / CDK

## CloudFormation / CDK: Express mode で開発デプロイを高速化

**概要**: AWS CloudFormation / AWS CDK の Express mode は、CloudFormation がリソース設定の適用を確認した時点でスタック操作を完了扱いにし、長い安定化待ち（CloudFront 伝播、トラフィック readiness、クリーンアップ等）を待たない高速デプロイモード。AWS の告知では内部ベンチマークで最大 4 倍高速化。

**基本方針**: 開発・検証環境の反復デプロイでは、原則 Express mode を使う。特に AI エージェントが CDK を何度も deploy する作業では優先する。

```bash
# CDK CLI
cdk deploy --express

# AWS CLI / SDK / Console で CloudFormation を直接扱う場合
aws cloudformation create-change-set \
  --deployment-config '{"mode":"EXPRESS"}'
```

**注意**:
- Express mode はデフォルトで rollback が無効になる。失敗時は即修正して再試行しやすいが、本番・共有基盤・データ保持リソースの変更では慎重に判断する。
- CloudFormation は依存順序と同一スタック内の依存リソース失敗処理は維持するが、伝播や安定化はバックグラウンドで継続する。
- 既存テンプレート変更は不要で、nested stacks にも対応。
- 古い CDK CLI では `--express` が使えない。`cdk deploy --help` に `--express` が出ない場合は CDK CLI を最新化する。

**確認済み情報（2026-07-02 JST）**:
- AWS What's New: "AWS CloudFormation and CDK express mode speeds up infrastructure deployments by up to 4x"（2026-06-30）
- CDK CLI `aws-cdk@2.1129.0` で `cdk deploy --express` が利用可能。

## CDK Lambda: ARM64バンドリングでImportModuleError

**症状**: Lambda実行時に `ImportModuleError` が発生（pydantic_core等のネイティブバイナリ）

**原因**: Lambdaに `architecture: ARM_64` を指定したが、バンドリング時の `platform` が一致していない

**解決策**: Lambda定義とバンドリングの両方でARM64を指定

```typescript
const fn = new lambda.Function(this, 'MyFunction', {
  runtime: lambda.Runtime.PYTHON_3_13,
  architecture: lambda.Architecture.ARM_64,  // ARM64を指定
  code: lambda.Code.fromAsset(path.join(__dirname, '../lambda'), {
    bundling: {
      image: lambda.Runtime.PYTHON_3_13.bundlingImage,
      platform: "linux/arm64",  // ← これが必要！
      command: [
        "bash", "-c",
        "pip install -r requirements.txt -t /asset-output && cp *.py /asset-output",
      ],
    },
  }),
});
```

## CDK TypeScript: import.meta.url は CommonJS モードで使えない

**症状**:
```
error TS1470: The 'import.meta' meta-property is not allowed in files which will build into CommonJS output.
```

**原因**: `tsconfig.json` が `"module": "NodeNext"` でも、`package.json` に `"type": "module"` がなければ CommonJS として扱われる。

**解決策**: CommonJS では `__dirname` がネイティブで使えるのでそのまま使う。

```typescript
// ❌ 不要
import { fileURLToPath } from 'url';
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// ✅ CommonJS ではネイティブで使える
dotenv.config({ path: path.join(__dirname, '../.env.local') });
```

---

## CDK CLI と aws-cdk-lib のバージョン不一致

**症状**:
```
Cloud assembly schema version mismatch: Maximum schema version supported is 49.x.x, but found 50.0.0.
You need at least CLI version 2.1105.0 to read this manifest.
```

**原因**: `package.json` の `aws-cdk`（CLI）が古く、`aws-cdk-lib`（ライブラリ）とのスキーマバージョンが合わない。

**重要**: `aws-cdk`（CLI）と `aws-cdk-lib`（ライブラリ）はバージョン体系が異なる。
- CLI: `2.1100.x`, `2.1108.x` のような大きい番号
- ライブラリ: `2.232.x`, `2.240.x` のような番号

**解決策**:
```bash
npm view aws-cdk version    # 最新 CLI バージョンを確認 → 例: 2.1108.0
# package.json の aws-cdk を最新版に更新して npm install
```

---

