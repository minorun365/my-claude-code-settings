---
name: sync-knowledge
description: プロジェクトで得た学びをグローバルナレッジベース（~/.claude/rules/）に反映する。新しい技術的知見やトラブルシューティング情報を蓄積
user-invocable: true
---

# ナレッジベース更新

現在のプロジェクトで得た学びを `~/.claude/rules/` 配下のナレッジベースに反映してください。

## 対象ファイル

| ファイル | 内容 |
|---------|------|
| `aws-learnings.md` | AWS全般（IAM、Cognito等） |
| `amplify-cdk.md` | Amplify Gen2 + CDK統合 |
| `bedrock-agentcore.md` | AgentCore Runtime |
| `strands-agents.md` | Strands Agentsフレームワーク |
| `frontend-patterns.md` | React、Tailwind、フロントエンド |
| `llm-app-patterns.md` | LLMアプリ開発パターン |
| `python-tools.md` | Python開発ツール（uv等） |
| `troubleshooting.md` | 遭遇した問題と解決策 |

## 実行手順

1. **プロジェクトの学びを確認**
   - プロジェクトの `/docs` 配下のドキュメント（KNOWLEDGE.md等）を確認
   - 今回のセッションで解決した問題や得た知見を整理

2. **該当するルールファイルを特定**
   - 学びの内容に応じて、上記のどのファイルに追記すべきか判断
   - 新しいカテゴリが必要な場合は、適切な名前で新規ファイルを作成

3. **ナレッジベースを更新**
   - `~/.claude/rules/` 配下の該当ファイルを読み込み
   - プロジェクト固有でない汎用的な学びを追記
   - コード例や具体的な解決策を含める

4. **更新内容を報告**
   - どのファイルに何を追記したかをユーザーに報告

## 注意事項

- プロジェクト固有の情報（APIキー、固有のリソース名等）は含めない
- 既存の内容と重複しないよう確認
- 他のプロジェクトでも再利用できる汎用的な形式で記述
