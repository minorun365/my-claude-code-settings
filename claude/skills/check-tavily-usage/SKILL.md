---
name: check-tavily-usage
description: プロジェクトの.envにある全Tavily APIキーの無料クレジット残量を確認する
argument-hint: [.envファイルのパス（省略可）]
---

# Tavily APIキー残量チェック

プロジェクトの `.env` ファイルにあるすべてのTavily APIキーの使用量・残量を確認してください。

## 手順

1. `.env` ファイルを読み込む
   - $ARGUMENTS が指定されていればそのパスを使用
   - 指定がなければカレントディレクトリの `.env` を使用
2. `TAVILY_API_KEY` を含む環境変数をすべて抽出する（`TAVILY_API_KEY`, `TAVILY_API_KEY2`, `TAVILY_API_KEY3` など）
3. 各キーに対して `curl -s "https://api.tavily.com/usage" -H "Authorization: Bearer {キー}"` を実行
4. 結果を以下の表形式でまとめる

## 出力形式

| # | 環境変数名 | プラン | 使用量 | 上限 | 残り |
|---|-----------|--------|--------|------|------|

- 枯渇（残り0）のキーには警告マークをつける
- 余裕があるキーには正常マークをつける
