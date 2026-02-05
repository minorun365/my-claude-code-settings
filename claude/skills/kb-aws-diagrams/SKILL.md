---
name: kb-aws-diagrams
description: AWS Diagram MCP Server（アーキテクチャ図、カスタムアイコン、レイアウト調整）
user-invocable: true
---

# AWS Diagram MCP Server ナレッジベース

AWS Diagram MCP Serverを使ったアーキテクチャ図作成のベストプラクティス集。

## 基本的なワークフロー

1. **`list_icons`** でアイコン一覧を取得
2. **`get_diagram_examples`** で例を確認（aws, custom 等）
3. **`generate_diagram`** で図を生成

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
~/.claude/skills/kb-aws-diagrams/icons/
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
└── Arch_Amazon-Elastic-Container-Service_64.png  # ECS
```

**使用例:**

```python
import os
ICON_DIR = os.path.expanduser("~/.claude/skills/kb-aws-diagrams/icons")

agentcore_icon = f"{ICON_DIR}/Arch_Amazon-Bedrock-AgentCore_64.png"
strands_icon = f"{ICON_DIR}/strands-agents.png"
```

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
    "splines": "ortho"  # 直角の矢印（polyline, spline も可）
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

### 分岐先が縦に並んでしまう

- `direction="LR"`の場合、分岐先は縦に並ぶ傾向がある
- `Edge(style="invis")`で横並びを強制できる

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
