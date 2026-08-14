# Strands Agents ナレッジ

AWS が提供する AI エージェントフレームワーク「Strands Agents」に関する学びを記録する。
CDK/デプロイ/ランタイムは `/kb-agentcore-cdk`、Observabilityは `/kb-agentcore-observability` を参照。

## 基本情報

### Strands Agents
- 公式: https://strandsagents.com/
- GitHub: https://github.com/strands-agents/strands-agents
- Python 3.10以上が必要

### Bedrock AgentCore
- 対応リージョンは拡大が続いている。**数や可否を覚えず、使う前に確認する**
  （`aws bedrock-agentcore-control help` の対応リージョン、または公式のリージョン別提供状況ページ）
- **機能単位で提供リージョンが違う**（Runtime は使えても Evaluations は未提供、といったことが起きる）。
  「このリージョンで AgentCore が使える」を機能ごとの可否の根拠にしない

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

