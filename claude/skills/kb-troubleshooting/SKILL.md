---
name: kb-troubleshooting
description: エラー・不具合が起きたときの最初の参照先。AWS/LLMアプリ/Claude Code/AgentCore/フロントエンド/クラウド/外部MCP別にどのナレッジスキルを呼ぶべきかをルーティングする
user-invocable: true
model: sonnet
---

# トラブルシューティング集

カテゴリ別に分割されています。該当するスキルを参照してください：

## トラブル発生領域別

| スキル | 内容 |
|--------|------|
| `/kb-ts-aws` | AWS全般（Cognito、Bedrock、Amplify、CDK、CloudWatch、AWS Agent Toolkit / uvx系接続エラー等） |
| `/kb-ts-llm-app` | LLMアプリ（ストリーミング処理、Tavily、エクスポート） |
| `/kb-ts-claude-code` | Claude Code設定（permissions、CLAUDE.md、settings.json） |

## AWS公式プラグイン（agent-toolkit-for-aws）の Skills

トラブル内容によっては以下が**自動起動**するので任せてOK：

| 領域 | 自動起動するSkill |
|------|------------------|
| CDK / CloudFormation エラー | `aws-core:aws-cdk` / `aws-core:aws-cloudformation` |
| Lambda / API Gateway / Step Functions | `aws-core:aws-serverless` |
| CloudWatch / X-Ray / 監視周り | `aws-core:aws-observability` |
| ECS / Fargate / ECR | `aws-core:aws-containers` |
| Amplify Gen2 | `aws-core:aws-amplify` |
| IAM / STS | `aws-core:aws-iam` |
| Bedrock / Knowledge Base / Guardrail | `aws-core:amazon-bedrock` |
| AgentCore Runtime デプロイ失敗 | `aws-agents:agents-deploy` |
| AgentCore エージェント挙動異常 | `aws-agents:agents-debug` |
| AgentCore Gateway / 外部API連携 | `aws-agents:agents-connect` |
| AgentCore 本番ハーデニング | `aws-agents:agents-harden` |
| AgentCore 評価 / 監視 / コスト | `aws-agents:agents-optimize` |

**みのるん固有のナレッジ（ハマりポイント、CDKコード例等）は引き続き `/kb-agentcore-cdk` 等の自作 kb-* skill を使う**。両者は補完関係。

## 技術・プロダクト別

### AgentCore
- `/kb-agentcore-cdk` — CDK・ランタイム統合、Browser Tool、Dockerfile
- `/kb-agentcore-identity` — Identity（3LO/M2M、OAuth）
- `/kb-agentcore-observability` — OpenTelemetry、ログ、トレース

### フロントエンド
- `/kb-frontend` — React / Tailwind / モバイルUI 全般
- `/kb-frontend-sse` — SSEストリーミング
- `/kb-frontend-amplify-ui` — Amplify UI React（Authenticator等）
- `/kb-web-audio` — Web Audio API / 音声対話UI

### クラウド・インフラ
- `/kb-amplify-cdk` — Amplify Gen2 + CDK
- `/kb-ec2-ssm` — EC2 + SSM Session Manager
- `/kb-google-cloud` — GCP / Vertex AI / ADK

### エージェント系フレームワーク
- `/kb-strands-agentcore` — Strands Agents
- `/kb-bidi-agent` — BidiAgent / Nova Sonic
- `/kb-kimi` — Kimi K2（Moonshot AI）

### SaaS・外部サービス連携
- `/kb-line` — LINE Bot
- `/kb-google-workspace-mcp` — Google Workspace MCP

### ツール・運用
- `/kb-marp` — Marp（スライド生成）
- `/kb-aws-diagrams` — AWS Diagram MCP Server
- `/kb-1password-cli` — 1Password CLI（op）

## PDF赤字読み取り

- PDF注釈のコメント・座標・矢印だけで削除範囲を断定しない。取り消し線、下線、囲みなどPDF上の実マークを拡大確認し、赤字対象が1文字だけなのか語句全体なのかを必ず切り分ける。
- 特に「☆削除」の注釈は、コメント位置の近くにある文全体ではなく、取り消し線が引かれた読点や助詞などの1文字だけを指すことがある。Before/Afterを作る前に、該当ページの画像で赤字マークそのものを確認する。
