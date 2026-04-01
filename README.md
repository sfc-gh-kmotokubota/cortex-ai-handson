# 証券営業インテリジェンス ハンズオン
## Nomura Holdings × Snowflake Cortex AI

このリポジトリは、Snowflake Cortex AI を使った証券営業向けインテリジェンスシステムの**ハンズオン教材**です。

---

## デモシナリオ

> **「証券営業担当者がAIを使って提案準備を10分で完了する」**
>
> 顧客・山田太郎様（68歳、元上場企業役員、預かり資産8億円）から  
> 「孫の海外留学費用として2,000万円が必要。トヨタ株を売りたい」という相談が入りました。
>
> AIアシスタントが顧客データ・市場ニュース・商品情報を統合し、  
> **「証券担保ローン」という最適な提案を自動的に導き出します。**

---

## ハンズオン構成

| ノートブック | 内容 | 所要時間 |
|---|---|---|
| [`00_setup.ipynb`](00_setup.ipynb) | 環境セットアップ・テーブル定義 | 10分 |
| [`01_data_generation.ipynb`](01_data_generation.ipynb) | ダミーデータ生成（300人の顧客データ）| 15分 |
| [`02_ai_functions.ipynb`](02_ai_functions.ipynb) | **Cortex AI Functions** (AI_SUMMARIZE/SENTIMENT/EXTRACT/CLASSIFY) | 20分 |
| [`03_cortex_analyst.ipynb`](03_cortex_analyst.ipynb) | **Cortex Analyst** (Semantic View + 自然言語 to SQL) | 20分 |
| [`04_cortex_search.ipynb`](04_cortex_search.ipynb) | **Cortex Search** (セマンティック検索) | 15分 |
| [`05_cortex_agent.ipynb`](05_cortex_agent.ipynb) | **Cortex Agent** (Snowflake Intelligence) | 20分 |

**合計: 約1.5時間**

---

## アーキテクチャ

```
Snowflake Intelligence (UI)
         │
   Cortex Agent（オーケストレーター）
   ├── Cortex Analyst ──── CUSTOMER_WEALTH_SEMANTIC_VIEW
   │   （顧客資産DB）          └─ 顧客・家族・ポートフォリオ・取引・相続税
   │
   ├── Cortex Search  ──── NEWS_SEARCH_SERVICE（ニュース50件）
   │   （非構造化検索）         LOAN_DOCS_SEARCH_SERVICE（商品説明書15件）
   │                          ANALYST_REPORT_SEARCH_SERVICE（レポート30件）
   │
   └── Cortex Analyst ──── TRUST_PRODUCT_SEMANTIC_VIEW
       （信託商品DB）           └─ 証券担保ローン・教育信託・遺言信託等
```

---

## データ構成

### 顧客資産管理DB（Cortex Analyst 1）

| テーブル | 件数 | 説明 |
|---|---|---|
| DIM_CUSTOMER | 300人 | 顧客マスタ（富裕層） |
| DIM_FAMILY | 約600件 | 家族構成・相続人情報 |
| DIM_LIFE_EVENT | 約200件 | ライフイベント（教育・相続・不動産）|
| FACT_PORTFOLIO | 約1,500件 | 保有資産明細 |
| FACT_TRANSACTION | 500件 | 取引履歴 |

### 信託銀行商品DB（Cortex Analyst 2）

| テーブル | 件数 | 説明 |
|---|---|---|
| DIM_TRUST_PRODUCT | 10商品 | 証券担保ローン・教育信託等 |
| DIM_PRODUCT_RECOMMENDATION | 30件 | 推奨ロジック |

### Cortex Search用

| サービス | 件数 | 説明 |
|---|---|---|
| NEWS_SEARCH_SERVICE | 50件 | マーケットニュース・税制改正 |
| LOAN_DOCS_SEARCH_SERVICE | 15件 | ローン商品説明書（チャンク分割済み）|
| ANALYST_REPORT_SEARCH_SERVICE | 30件 | アナリストレポート |

---

## セットアップ手順

### Option A: Snowflake Notebook で実行（推奨）

1. 各 `.ipynb` ファイルを Snowsight の「Notebook」にアップロード
2. `00_setup.ipynb` から順番に実行

### Option B: setup.sql で一括実行

```sql
-- Snowsight ワークシートで setup.sql を実行（約1,900行）
```

### 前提条件

- Snowflake アカウント（Enterprise以上推奨）
- ACCOUNTADMIN ロール
- Cortex AI 機能が有効なリージョン（AWS US East/West推奨）

---

## アハ体験ポイント

### 1. AI Functions（Part 2）
> 1,000文字のアナリストレポートが **3秒で3行に要約** される
> → RM が毎朝1時間かけて読んでいた記事を瞬時に整理

### 2. Cortex Analyst（Part 3）
> 「教育資金のライフイベントがあって緊急度が高い顧客リストを出して」
> → SQLを知らない営業担当者でも **日本語だけ**で複雑なデータ分析が可能

### 3. Cortex Search（Part 4）
> 「株を売らずに資金を調達する方法」と検索 → **「証券担保ローン」**の説明書がヒット
> → キーワードではなく **意味**で検索するため、お客様の言葉そのままで使える

### 4. Cortex Agent（Part 5）: データが増えるとAIが賢くなる！
> | ツール | 回答の質 |
> |---|---|
> | 顧客DBのみ | 「売却手続きを進めましょう」（弱い）|
> | + ニュース/商品書類 | 「証券担保ローンをお勧めします」（強い）|
> | + 信託商品DB | 「教育資金贈与信託も2026年3月までに！」（完璧）|

---

## デモ用質問例

### 事前確認
```
C001の山田太郎様の顧客プロフィールとポートフォリオを教えてください
```

### Step 1-2: 初期相談（弱い回答を期待）
```
C001の山田様から株式売却の相談がありました。
孫の留学費用として2,000万円が必要とのことです。
トヨタ株の売却についてアドバイスをください。
```

### Step 4: データ追加後（強い回答を期待）
```
今の状況を踏まえて、C001の山田様に最適な提案は何ですか？
信託銀行の商品も含めて検討してください。
```

### Step 6: 長期提案
```
C001の山田様は相続対策にも関心があるようです。
長期的な観点からのアドバイスもお願いします。
```

---

## 注意事項

- このデモはすべて**架空のデータ**を使用しています
- 「プレミアム証券」「プレミアム信託銀行」は架空の企業名です
- 税制情報はデモ用の簡易計算であり、実際の税制とは異なる場合があります
- Cortex Search の初回インデックス構築には数分かかる場合があります

---

## 参照リポジトリ

- [sales_assistant_agent_by_snowflake_intelligence](https://github.com/kmotokubota/sales_assistant_agent_by_snowflake_intelligence) - 本ハンズオンの最終アウトプット（Snowflake Intelligence デモ）
- [cortex-handson-jp](https://github.com/snow-jp-handson-org/cortex-handson-jp) - Cortex AI ハンズオン参考資料

---

*Powered by Snowflake Cortex AI*
