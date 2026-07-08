# Strands Agents ナレッジ overview

# Strands Agents ナレッジ

AWS が提供する AI エージェントフレームワーク「Strands Agents」に関する学びを記録する。
CDK/デプロイ/ランタイムは `/kb-agentcore-cdk`、Observabilityは `/kb-agentcore-observability` を参照。

## 基本情報

### Strands Agents
- 公式: https://strandsagents.com/
- GitHub: https://github.com/strands-agents/strands-agents
- Python 3.10以上が必要

### Bedrock AgentCore
- 15リージョンで利用可能（us-east-1, us-west-2, ap-northeast-1 等）
- Evaluations機能のみ一部リージョン限定（東京は非対応）

## インストール

```bash
# pip
pip install strands-agents bedrock-agentcore

# uv
uv add strands-agents bedrock-agentcore
```

### AWS CLI login 認証を使う場合
```bash
uv add 'botocore[crt]'
```
`aws login` で認証した場合、botocore[crt] が必要。これがないと認証エラーになる。

---

