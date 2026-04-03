# 証券営業インテリジェンス ハンズオン

Snowflake Cortex AI を使った証券営業インテリジェンスシステムをゼロから構築するハンズオンコンテンツです。

## 概要

顧客資産データ・ファンド目論見書・マーケットニュース・アナリストレポートを統合し、
自然言語で分析・提案ができるAIアシスタントを構築します。

**想定時間**: 約4時間  
**対象**: 技術者・ビジネス担当者（混在可）

---

## ノートブック構成

| # | ファイル | 概要 | 所要時間 |
|---|---|---|---|
| 事前準備 | `setup.sql` | DB・スキーマ・テーブル・データ生成・ウェアハウス作成 | 10分 |
| Part 1 | `part1_security.ipynb` | Cortex AI セキュリティ設定・アクセス制御 | 30分 |
| Part 2 | `part2_ai_functions.ipynb` | AI Functions（要約・感情分析・抽出・分類・マスキング・類似度） | 55分 |
| Part 3 | `part3_cortex_analyst.ipynb` | Semantic View 作成と Cortex Analyst（自然言語 to SQL） | 45分 |
| Part 4 | `part4_cortex_search.ipynb` | PDF 解析・Cortex Search Service 作成・セマンティック検索 | 60分 |
| Part 5 | `part5_cortex_agent.ipynb` | Cortex Agent 作成と Snowflake Intelligence デモ | 40分 |

---

## セットアップ

### 前提条件
- Snowflake アカウント（`ACCOUNTADMIN` ロール推奨）
- Snowsight へのアクセス

### 手順

#### Step 1 — setup.sql の実行

1. Snowsight の **SQL Editor** を開く
2. `setup.sql` の内容を貼り付けてすべて実行する
3. `SNOWFINANCE_DB` / `DEMO_SCHEMA` と各テーブル・ウェアハウスが作成される

#### Step 2 — Workspace に Git リポジトリを追加

1. Snowsight の左メニューから **Workspace** を開く
2. 「**+ 追加**」→「**Git リポジトリから**」をクリック
3. 以下を入力する

   | 項目 | 値 |
   |---|---|
   | URL | `https://github.com/kmotokubota/cortex-ai-handson` |
   | 認証 | **API インテグレーション**を選択 |
   | 種別 | **パブリックリポジトリ**として作成 |

4. 「作成」をクリックするとノートブックが Workspace に追加される

#### Step 3 — ノートブックを順番に実行

Workspace に追加されたリポジトリから `part1` → `part5` の順に開いて実行する。

```
setup.sql（SQL Editor）
  ↓
part1_security → part2_ai_functions → part3_cortex_analyst
  → part4_cortex_search → part5_cortex_agent
```

> **注意**: 各 Part は前の Part の実行結果に依存しています。必ず順番通りに実行してください。

### ウェアハウス

| ウェアハウス | サイズ | 用途 |
|---|---|---|
| `DEMO_WH` | XSMALL | 通常のSQL・AI Functions・Cortex Analyst |
| `COMPUTE_WH` | XSMALL | Cortex Search インデックス構築 |

---

## アーキテクチャ

```
顧客データ（DIM_CUSTOMER / FACT_PORTFOLIO / ...）  100名分
ファンド目論見書 PDF（@PROSPECTUS_STAGE）
マーケットニュース（NEWS_ARTICLES）               50件
アナリストレポート（ANALYST_REPORTS）             30件
        │
        ├── Cortex AI Functions ─────── テキスト要約・感情分析・抽出・分類（Part 2）
        │
        ├── Cortex Analyst ──────────── 自然言語 to SQL（Part 3）
        │       └── CUSTOMER_WEALTH_SEMANTIC_VIEW
        │       └── TRUST_PRODUCT_SEMANTIC_VIEW
        │
        ├── Cortex Search ───────────── PDF 解析 + セマンティック検索（Part 4）
        │       └── NEWS_SEARCH_SERVICE
        │       └── LOAN_DOCS_SEARCH_SERVICE
        │       └── ANALYST_REPORT_SEARCH_SERVICE
        │       └── FUND_DOCS_SEARCH_SERVICE（目論見書 PDF）
        │
        └── Cortex Agent ────────────── Snowflake Intelligence（Part 5）
                └── WEALTH_MANAGEMENT_ASSISTANT_AGENT
```

---

## デモシナリオ

```
顧客: 山田太郎様（68歳・元上場企業役員・預かり資産8億円）
相談: 「孫の海外留学費用2,000万円のためにトヨタ株を売りたい」

AIの提案:
  ├── トヨタ株の含み益 → 売却時の税負担を試算
  ├── 証券担保ローンの活用 → 株を売らずに資金調達
  ├── ファンド目論見書検索 → 分散投資の提案材料
  └── 教育資金贈与信託 → 非課税での孫への資金移転
```

---

## 体験ポイント

### AI Functions（Part 2）
> 「2,000文字のアナリストレポートが3行に。訪問準備1時間が10秒に。」

### Cortex Analyst（Part 3）
> 「SQLを書かずに、日本語で『預かり資産5億円以上の顧客は？』と聞くだけで答えが返ってくる。」

### Cortex Search（Part 4）
> 「『証券担保ローン』を知らなくても『株を売らずにお金を借りたい』で商品説明書がヒットする。」

### Cortex Agent（Part 5）
> 「顧客データ・ニュース・目論見書・商品情報を横断した回答が1つのUIから得られる。
>  Snowflake にデータを集めるだけで、AIが自動的に最適なツールを選択して回答する。」

---

## Snowflake オブジェクト一覧

| 種別 | オブジェクト名 | 役割 |
|---|---|---|
| Database | `SNOWFINANCE_DB` | ハンズオン用データベース |
| Schema | `DEMO_SCHEMA` | 全オブジェクトのスキーマ |
| Warehouse | `DEMO_WH` | 通常処理用ウェアハウス |
| Warehouse | `COMPUTE_WH` | Cortex Search 用ウェアハウス |
| Semantic View | `CUSTOMER_WEALTH_SEMANTIC_VIEW` | 顧客資産の自然言語クエリ |
| Semantic View | `TRUST_PRODUCT_SEMANTIC_VIEW` | 信託商品の自然言語クエリ |
| Cortex Search | `NEWS_SEARCH_SERVICE` | ニュース検索 |
| Cortex Search | `LOAN_DOCS_SEARCH_SERVICE` | ローン商品説明書検索 |
| Cortex Search | `ANALYST_REPORT_SEARCH_SERVICE` | アナリストレポート検索 |
| Cortex Search | `FUND_DOCS_SEARCH_SERVICE` | ファンド目論見書検索 |
| Cortex Agent | `WEALTH_MANAGEMENT_ASSISTANT_AGENT` | 統合AIアシスタント |

---

## セキュリティ（Part 1 参照）

- **クロスリージョン制御**: データ処理リージョンを限定可能
- **CORTEX_USER RBAC**: AI機能を使えるロールを制限
- **監査ログ**: QUERY_HISTORY でAI使用状況をトレース
- **多層マスキング**: マスキングポリシー + AI_REDACT で個人情報保護

---

> ⚠️ このリポジトリのデータはすべて架空のダミーデータです。実際の顧客情報・商品情報は含まれていません。
