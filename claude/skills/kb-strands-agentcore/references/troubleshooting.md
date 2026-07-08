# トラブルシューティング・関連スキル・参考リンク

## トラブルシューティング

### AWS認証エラー
`aws login` で認証した場合、`botocore[crt]` が必要：
```bash
uv add 'botocore[crt]'
```

### モデルが見つからない
クロスリージョン推論のモデルID（`us.` プレフィックス）を使用しているか確認。
リージョンによって利用可能なモデルが異なる。

### ストリーミングが動かない
`stream()` と `stream_async()` を環境に合わせて使い分ける：
- 同期コンテキスト -> `stream()`
- 非同期コンテキスト（async/await） -> `stream_async()`

### Kimi K2関連

Kimi K2（Moonshot AI）特有の問題は `/kb-kimi` スキルを参照してください。

### 複数ツールの連続呼び出しで `MaxTokensReachedException`

1回の依頼で同種ツール（例: 事例登録ツール）を何度も呼ばせる設計だと、モデルが**複数の tool use を1つの応答にまとめて生成**しようとして出力トークン上限に達し、`MaxTokensReachedException` で応答が途中で切れる。tool use の引数が長い（資料本文の要約を渡す等）ほど起きやすい。1件のダミー入力では偶然収まり、実データ規模で初めて踏むことがある。

対策は2つセットで効く：

1. `BedrockModel` の `max_tokens` を明示的に広げる（デフォルトは小さめ）。
   ```python
   model = BedrockModel(region_name=REGION, model_id=MODEL_ID, max_tokens=16384)
   ```
2. システムプロンプトで「ツールは1回の応答につき1つだけ呼び、結果を確認してから次を呼ぶ。全部終わったら最後にまとめ返信ツールを呼ぶ」と明示し、1応答1ツールに寄せる。

### 検索基盤の同期ラグがある重複チェックはプロンプトでなくコードで

「登録前に既存を検索して重複を防ぐ」を Knowledge Base 検索ツール（`retrieve_*`）で LLM にやらせると、**KB の同期が数分〜十数分遅れる**ため直前に登録したばかりの項目を見逃し、重複登録がすり抜ける。LLM は指示どおり検索して「重複なし」と正しく判断していても、索引が古いのが原因。

整合性が要るガードはプロンプト任せにせず、**書き込み先（DynamoDB 等）を即時照合するコード**を登録ツール自身に持たせる。人間の明示指示でだけバイパスする `allow_duplicate` 相当のフラグを用意すると誤検知時も回避できる。教訓: 「プロンプトで指示したから安全」は、背後の基盤に結果整合性がある場合は成立しない。

---

## 関連スキル

- `/kb-agentcore-cdk` - AgentCore CDK、デプロイ、ランタイム統合、コンテナ構成
- `/kb-agentcore-observability` - OpenTelemetry、ログ、メトリクス、トレース
- `/kb-agentcore-identity` - アウトバウンド認証（3LO/M2M/デコレータ分離/callback等）
- `/kb-bidi-agent` - BidiAgent（双方向ストリーミング / 音声対話 / Nova Sonic）
- `/kb-kimi` - Kimi K2（Moonshot AI）特有の問題・ワークアラウンド

## 参考リンク

- [Strands Agents 公式ドキュメント](https://strandsagents.com/)
- [GitHub リポジトリ](https://github.com/strands-agents/strands-agents)
- [Bedrock AgentCore 統合ガイド](https://docs.aws.amazon.com/bedrock/latest/userguide/agents-agentcore.html)
