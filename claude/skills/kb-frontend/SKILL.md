---
name: kb-frontend
description: フロントエンド開発のナレッジ＆トラブルシューティング。React/Tailwind/ステータス管理/モバイルUI等
user-invocable: true
model: sonnet
---
# フロントエンド開発パターン

この `SKILL.md` は入口だけに絞っている。作業内容に近い参照ファイルを1〜2個だけ読み、不要な大型ナレッジをまとめて読まない。

## 参照ルール

1. まず依頼内容から必要な参照ファイルを選ぶ。
2. 最新仕様や外部サービス仕様が関係する場合は、参照ファイルだけで断定せず公式ドキュメント・MCP・実コードで確認する。
3. 複数領域にまたがる場合も、読み込む参照は最小限から始める。

## 参照ファイル

- `references/overview.md`: 元の概要・前提（SSEは /kb-frontend-sse、Amplify UIは /kb-frontend-amplify-ui への導線）
- `references/tailwind.md`: Tailwind CSS v4、Tailwind CSS Tips
- `references/streaming-ui.md`: React ストリーミングUI、疑似ストリーミング表示（1文字ずつ表示）
- `references/mobile-status-ui.md`: モバイルUI対応（iOS Safari）、ステータス表示パターン、モーダルの状態管理
- `references/react-misc.md`: 非同期コールバック内のエラーハンドリング、環境変数（.env vs .env.local）、OGP/Twitterカード、トラブルシューティング
- `references/chrome-devtools-spa.md`: Chrome DevTools MCP でのSPA/React操作
- `references/npm-publish.md`: npm パッケージ公開（CLIツール）
