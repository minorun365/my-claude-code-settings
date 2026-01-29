---
name: sync-knowledge
description: プロジェクトで得た学びをグローバルナレッジベース（~/.claude/skills/）に反映する。新しい技術的知見やトラブルシューティング情報を蓄積
user-invocable: true
---

# ナレッジベース更新

現在のプロジェクトで得た学びを `~/.claude/skills/` 配下のナレッジスキルに反映してください。

## 対象スキル

| スキル | パス | 内容 |
|--------|------|------|
| `/kb-strands-agentcore` | `~/.claude/skills/kb-strands-agentcore/skill.md` | Strands Agents + Bedrock AgentCore |
| `/kb-amplify-cdk` | `~/.claude/skills/kb-amplify-cdk/skill.md` | Amplify Gen2 + CDK |
| `/kb-frontend` | `~/.claude/skills/kb-frontend/skill.md` | React、Tailwind、Marp、SSE |
| `/kb-troubleshooting` | `~/.claude/skills/kb-troubleshooting/skill.md` | トラブルシューティング集 |

## 実行手順

1. **プロジェクトの学びを確認**
   - プロジェクトの `/docs` 配下のドキュメント（KNOWLEDGE.md等）を確認
   - 今回のセッションで解決した問題や得た知見を整理

2. **該当するスキルファイルを特定**
   - 学びの内容に応じて、上記のどのスキルに追記すべきか判断
   - 新しいカテゴリが必要な場合は、`kb-xxx` 形式で新規スキルを作成

3. **ナレッジベースを更新**
   - 該当スキルの `skill.md` を読み込み
   - プロジェクト固有でない汎用的な学びを追記
   - コード例や具体的な解決策を含める

4. **更新内容を報告**
   - どのスキルに何を追記したかをユーザーに報告

## 注意事項

- プロジェクト固有の情報（APIキー、固有のリソース名等）は含めない
- 既存の内容と重複しないよう確認
- 他のプロジェクトでも再利用できる汎用的な形式で記述

## 次のステップ

ナレッジベースを更新したら、GitHubへの同期も提案してください：

> 「ナレッジベースを更新しました。GitHubにもプッシュしておく？（`/sync-settings` で同期できるよ）」
