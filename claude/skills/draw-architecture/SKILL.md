---
name: draw-architecture
description: AWSアーキテクチャ図を生成する。diagrams(Python)ライブラリ + カスタムアイコンでPNG出力
user-invocable: true
---

# AWSアーキテクチャ図生成

Pythonの`diagrams`ライブラリを使ってAWSアーキテクチャ図を生成するスキル。カスタムアイコン同梱。

## 基本的なワークフロー

### Step 0: 依存チェック（図を生成する前に必ず実行）

以下のコマンドで依存関係を確認し、不足していれば自動インストールする：

```bash
# graphviz バイナリ（dot コマンド）のチェック＆インストール
which dot || brew install graphviz

# Python diagrams パッケージのチェック＆インストール
python -c "import diagrams" 2>/dev/null || pip install diagrams
```

**これを省略すると `ModuleNotFoundError` や `ExecutableNotFound` でコケるので必ず先に実行すること。**

### Step 1〜3: 図の生成

1. 同梱アイコン一覧（下記）を確認し、必要なアイコンを選定
2. Python スクリプトを `/tmp/` に書き出し
3. `python /tmp/スクリプト名.py` で図を生成

## Diagram Generation

AWSアーキテクチャ図を生成する際のベストプラクティス：

- **アイコンパスの検証**: アイコンを使用する前に、パスが存在するか必ず確認する。`diagrams` ライブラリの `diagrams.aws.*` モジュールに含まれるビルトインアイコンを優先的に使用する（カスタムパスより安全）
- **段階的な開発**: 複雑な図を作る前に、まずミニマルな図でテストしてから要素を追加していく

### レイアウトのベストプラクティス

- `graph_attr` で `rankdir`、`splines`、`nodesep` を明示的に設定し、要素の配置を制御する
- 要素がクラスター境界の外に出ないよう、Cluster（サブグラフ）内に配置する

## カスタムアイコンの使い方

最新のAWSアイコン（AgentCore等）を使う場合：

```python
from diagrams.custom import Custom

# ローカルのアイコンファイルを指定（絶対パス必須）
agentcore_icon = "/path/to/Arch_Amazon-Bedrock-AgentCore_64.png"
agentcore = Custom("AgentCore Runtime", agentcore_icon)
```

### スキル内の同梱アイコン（すぐ使える）

このスキルにはよく使うアイコンが同梱されています：

```
~/.claude/skills/draw-architecture/icons/
├── strands-agents.png              # Strands Agents
├── Arch_Amazon-Bedrock_64.png      # Bedrock
├── Arch_Amazon-Bedrock-AgentCore_64.png  # AgentCore（最新）
├── Arch_AWS-Amplify_64.png         # Amplify
├── Arch_Amazon-Cognito_64.png      # Cognito
├── Arch_Amazon-DynamoDB_64.png     # DynamoDB
├── Arch_Amazon-Simple-Storage-Service_64.png  # S3
├── Arch_AWS-Lambda_64.png          # Lambda
├── Arch_Amazon-API-Gateway_64.png  # API Gateway
├── Arch_Amazon-CloudFront_64.png   # CloudFront
├── Arch_Amazon-Elastic-Container-Service_64.png  # ECS
├── outlook.png                     # Microsoft Outlook
├── microsoft-todo.png              # Microsoft To Do
├── confluence.png                  # Confluence
└── entra.png                       # Microsoft Entra ID
```

**使用例:**

```python
import os
ICON_DIR = os.path.expanduser("~/.claude/skills/draw-architecture/icons")

agentcore_icon = f"{ICON_DIR}/Arch_Amazon-Bedrock-AgentCore_64.png"
strands_icon = f"{ICON_DIR}/strands-agents.png"
```

### 非AWSサービスのカスタムアイコン作成

Tavily、RSS など AWS 以外のサービスアイコンは SVG → PNG 変換で作成：

```bash
# 1. SVGを作成（例: RSSアイコン）
cat > /tmp/rss_icon.svg << 'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128"
     viewBox="0 0 24 24" fill="none" stroke="#FF9900" stroke-width="1.5">
  <path d="M4 11a9 9 0 0 1 9 9"/>
  <path d="M4 4a16 16 0 0 1 16 16"/>
  <circle cx="5" cy="19" r="1" fill="#FF9900"/>
</svg>
EOF

# 2. rsvg-convert で PNG に変換（macOS: brew install librsvg）
rsvg-convert -w 128 -h 128 /tmp/rss_icon.svg -o ./icons/rss.png

# 3. Custom で使用
rss = Custom("RSS", "./icons/rss.png")
```

**ポイント**: `stroke="#FF9900"` でAWSオレンジに統一すると見栄えが良い。

### AWS公式アイコンの入手（追加が必要な場合）

1. [AWS Architecture Icons](https://aws.amazon.com/architecture/icons/) からZIPをダウンロード
2. 解凍して64pxのPNGを使用（例: `Architecture-Service-Icons_*/Arch_*/64/*.png`）
3. 四半期ごとに更新される（Q1: 1月末、Q2: 4月末、Q3: 7月末）

## レイアウト調整

### 方向の指定

```python
# 左から右へ（横長）
with Diagram("名前", direction="LR"):

# 上から下へ（縦長）
with Diagram("名前", direction="TB"):
```

### ノード間隔の調整

```python
with Diagram("名前", graph_attr={
    "nodesep": "0.5",   # ノード間の水平間隔
    "ranksep": "0.5",   # ランク間の垂直間隔
    "splines": "ortho"  # 直角の矢印
    # "polyline" → 滑らかな折れ線（分岐が多い図に最適、おすすめ）
    # "spline"  → 曲線（デフォルト）
}):
```

### クラスター内のノードを横並びにする

```python
with Cluster("Data Layer"):
    kb = Custom("Knowledge Base", kb_icon)
    dynamodb = Custom("DynamoDB", dynamodb_icon)
    s3 = Custom("S3", s3_icon)
    # 見えない線で横につなぐ
    kb - Edge(style="invis") - dynamodb - Edge(style="invis") - s3
```

## 矢印（Edge）の使い方

```python
# 矢印付き接続
node1 >> node2

# 矢印なし接続
node1 - node2

# 点線（認証フローなど）
node1 - Edge(style="dashed") - node2

# ラベル付き
node1 >> Edge(label="SSE") >> node2

# 色付き
node1 >> Edge(color="orange") >> node2

# 複数ノードへ一括接続
strands_agent >> [kb, dynamodb, s3]
```

## クラスターの使い方

```python
with Cluster("Bedrock AgentCore"):
    runtime = Custom("AgentCore Runtime", runtime_icon)
    agent = Custom("Strands Agent", agent_icon)
    llm = Custom("Claude Sonnet 4.5", bedrock_icon)
    # クラスター内の接続
    runtime >> agent >> llm
```

## 注意点・トラブルシューティング

### アイコンが表示されない

- パスが間違っている可能性。絶対パスを使用する
- ファイルが存在するか確認（`ls`で確認）

### ノードがクラスターの外に出る

- 接続順序を変更する
- クラスター内で接続を完結させる

### 分岐先が縦に並んでしまう（LR方向）

`direction="LR"`で1つのノードから複数に分岐すると、分岐先は縦に並ぶ。**横並びにするには Cluster + invisible edges が必要**：

```python
# NG: ツールが縦に並ぶ
agent >> [tavily, aws_docs, rss_feed]

# OK: Cluster内でinvisible edgesを使い横並びに
with Cluster("Tools"):
    tavily = Custom("Tavily", tavily_icon)
    aws_docs = Custom("AWS Docs", globe_icon)
    rss_feed = Custom("RSS", rss_icon)
    tavily - Edge(style="invis") - aws_docs - Edge(style="invis") - rss_feed

agent >> [tavily, aws_docs, rss_feed]
```

### saas/onprem アイコンと Cluster の組み合わせでエラー

`saas.chat.Line`、`onprem.network.Internet`、`aws.general.InternetAlt1` 等を **Cluster と組み合わせるとエラー**になることがある（エラーメッセージなしで生成失敗）。

**安定する組み合わせ**: `aws.general.User` + `diagrams.custom.Custom` のみ

```python
# NG: saas/onprem アイコンを Cluster と併用
from diagrams.saas.chat import Line
from diagrams.onprem.network import Internet
line_user = Line("LINE User")  # 別の Cluster があるとエラー

# OK: User + Custom のみ使用
from diagrams.aws.general import User
from diagrams.custom import Custom
line_user = User("LINE User")
tavily = Custom("Tavily", tavily_icon)
```

### エラー時のデバッグ手法

Diagram MCP Server はエラー詳細を返さないことが多い。**ミニマル構成から段階的に要素を追加**して原因を特定する：

1. 最小限の図（2ノード + 1エッジ）で動作確認
2. Cluster を1つ追加して確認
3. カスタムアイコンを追加して確認
4. 2つ目の Cluster を追加して確認 ← ここでエラーになりやすい

### 矢印の出発点がずれる

- graphvizの制約で、メインフローの最後のノードから分岐が描画されることがある
- 接続順序を調整するか、中間ノードを経由させる

## サンプルコード（完全版）

```python
ICON_BASE = "/path/to/Architecture-Service-Icons/Arch_*/64"

amplify_icon = f"{ICON_BASE}/Arch_AWS-Amplify_64.png"
cognito_icon = f"{ICON_BASE}/Arch_Amazon-Cognito_64.png"
agentcore_icon = f"{ICON_BASE}/Arch_Amazon-Bedrock-AgentCore_64.png"
bedrock_icon = f"{ICON_BASE}/Arch_Amazon-Bedrock_64.png"
dynamodb_icon = f"{ICON_BASE}/Arch_Amazon-DynamoDB_64.png"
s3_icon = f"{ICON_BASE}/Arch_Amazon-Simple-Storage-Service_64.png"
strands_icon = "/path/to/strands-agents.png"

from diagrams.custom import Custom

with Diagram("Architecture", show=False, direction="LR", graph_attr={"nodesep": "0.3", "ranksep": "0.5"}):
    user = User("ユーザー")

    amplify = Custom("Amplify Gen2", amplify_icon)
    cognito = Custom("Cognito", cognito_icon)

    with Cluster("Bedrock AgentCore"):
        runtime = Custom("AgentCore Runtime", agentcore_icon)
        agent = Custom("Strands Agent", strands_icon)
        llm = Custom("Claude Sonnet 4.5", bedrock_icon)

    with Cluster("Data Layer"):
        kb = Custom("Knowledge Base", bedrock_icon)
        dynamodb = Custom("DynamoDB", dynamodb_icon)
        s3 = Custom("S3", s3_icon)
        kb - Edge(style="invis") - dynamodb - Edge(style="invis") - s3

    user >> amplify >> runtime >> agent >> llm
    amplify - Edge(style="dashed") - cognito

    agent >> kb
    agent >> dynamodb
    agent >> s3
```

## 参考リンク

- [AWS Architecture Icons](https://aws.amazon.com/architecture/icons/)
- [mingrammer/diagrams GitHub](https://github.com/mingrammer/diagrams)
- [Diagrams ドキュメント](https://diagrams.mingrammer.com/)
