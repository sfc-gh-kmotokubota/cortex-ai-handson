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
| 00 | `00_setup.ipynb` | DB・スキーマ・テーブル・ウェアハウス作成 | 15分 |
| 01 | `01_data_generation.ipynb` | 50名分のダミーデータ生成 | 15分 |
| 02 | `02_security.ipynb` | Cortex AI セキュリティ設定・アクセス制御 | 20分 |
| 03 | `03_ai_functions.ipynb` | AI Functions（要約・感情分析・抽出・分類・マスキング・類似度） | 55分 |
| 04 | `04_fund_docs.ipynb` | ファンド目論見書 PDF の解析と検索インデックス構築 | 30分 |
| 05 | `05_cortex_analyst.ipynb` | Semantic View 作成と Cortex Analyst（自然言語 to SQL） | 40分 |
| 06 | `06_cortex_search.ipynb` | Cortex Search Service 作成とセマンティック検索 | 40分 |
| 07 | `07_cortex_agent.ipynb` | Cortex Agent 作成と Snowflake Intelligence デモ | 40分 |

---

## アーキテクチャ

```
顧客データ（DIM_CUSTOMER / FACT_PORTFOLIO / ...）
ファンド目論見書 PDF（docs/）
マーケットニュース（NEWS_ARTICLES）
アナリストレポート（ANALYST_REPORTS）
        │
        ├── Cortex AI Functions ─────── テキスト要約・感情分析・抽出・分類
        │
        ├── Cortex Analyst ──────────── 自然言語 to SQL（Semantic View経由）
        │       └── CUSTOMER_WEALTH_SEMANTIC_VIEW
        │       └── TRUST_PRODUCT_SEMANTIC_VIEW
        │
        ├── Cortex Search ───────────── セマンティック検索
        │       └── NEWS_SEARCH_SERVICE
        │       └── LOAN_DOCS_SEARCH_SERVICE
        │       └── ANALYST_REPORT_SEARCH_SERVICE
        │       └── FUND_DOCS_SEARCH_SERVICE（目論見書）
        │
        └── Cortex Agent ────────────── Snowflake Intelligence
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

## セットアップ

### 前提条件
- Snowflake アカウント（`ACCOUNTADMIN` ロール推奨）
- Snowflake Notebook（Snowsight）へのアクセス
- `docs/` フォルダへの PDF 配置（`docs/README.md` 参照）

### 実行順序

```
00_setup → 01_data_generation → 02_security → 03_ai_functions
→ 04_fund_docs → 05_cortex_analyst → 06_cortex_search → 07_cortex_agent
```

### ウェアハウス
| ウェアハウス | 用途 |
|---|---|
| `DEMO_WH` (MEDIUM) | 通常のSQL・AI Functions |
| `COMPUTE_WH` (MEDIUM) | Cortex Search インデックス構築 |

---

## 4つのアハ体験ポイント

### 1. AI Functions（Part 3）
> 「2,000文字のアナリストレポートが3行に。訪問準備1時間が10秒に。」

### 2. Cortex Analyst（Part 5）
> 「SQLを書かずに、日本語で『預かり資産5億円以上の顧客は？』と聞くだけで答えが返ってくる。」

### 3. Cortex Search（Part 6）
> 「『証券担保ローン』を知らなくても『株を売らずにお金を借りたい』で目論見書がヒットする。」

### 4. Cortex Agent（Part 7）
> 「顧客データ・ニュース・目論見書・商品情報を横断した回答が1つのUIから得られる。
>  ツールを追加するほどAIの回答が賢くなる。」

---

## Snowflake オブジェクト一覧

| 種別 | オブジェクト名 | 役割 |
|---|---|---|
| Database | `SNOWFINANCE_DB` | ハンズオン用データベース |
| Schema | `DEMO_SCHEMA` | 全オブジェクトのスキーマ |
| Semantic View | `CUSTOMER_WEALTH_SEMANTIC_VIEW` | 顧客資産の自然言語クエリ |
| Semantic View | `TRUST_PRODUCT_SEMANTIC_VIEW` | 信託商品の自然言語クエリ |
| Cortex Search | `NEWS_SEARCH_SERVICE` | ニュース検索 |
| Cortex Search | `LOAN_DOCS_SEARCH_SERVICE` | ローン商品説明書検索 |
| Cortex Search | `ANALYST_REPORT_SEARCH_SERVICE` | アナリストレポート検索 |
| Cortex Search | `FUND_DOCS_SEARCH_SERVICE` | ファンド目論見書検索 |
| Cortex Agent | `WEALTH_MANAGEMENT_ASSISTANT_AGENT` | 統合AIアシスタント |

---

## セキュリティ（Part 2 参照）

- **クロスリージョン制御**: データ処理リージョンを限定可能
- **CORTEX_USER RBAC**: AI機能を使えるロールを制限
- **監査ログ**: QUERY_HISTORY でAI使用状況をトレース
- **多層マスキング**: マスキングポリシー + AI_REDACT で個人情報保護

---

> ⚠️ このリポジトリのデータはすべて架空のダミーデータです。実際の顧客情報・商品情報は含まれていません。
