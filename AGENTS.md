# AGENTS.md - 証券営業インテリジェンス Cortex AI ハンズオン

## プロジェクト概要

プレミアム証券（架空）の顧客データを使った Snowflake Cortex AI ハンズオンコンテンツです。
顧客資産データ・ファンド目論見書・マーケットニュース・アナリストレポートを統合し、
証券営業担当者を支援するAIアシスタントをゼロから構築します。

## 言語に関する注意事項

このプロジェクトは**日本語話者向けのハンズオン**です。以下を厳守してください：

- **会話・応答はすべて日本語**で行うこと
- **コード内のコメントは日本語**で記述すること
- **マークダウンセルの説明文は日本語**で記述すること
- **ログ・ステータスメッセージは日本語**で出力すること（例: `'【完了】テーブルを作成しました'`）
- SQL・Python のキーワード・関数名はそのままで構いません

## プロジェクト構成

```
/
├── setup.sql                    # 環境セットアップ（Git連携・DB・テーブル・ニュース/アナリストデータ）
├── docs/                        # ファンド目論見書 PDF（AI_PARSE_DOCUMENT で使用）
├── 00_setup.ipynb               # DB・スキーマ・ウェアハウス・テーブル作成
├── 01_data_generation.ipynb     # 50名ダミーデータ生成（ストアドプロシージャ）
├── 02_security.ipynb            # Cortex AI セキュリティ・アクセス制御
├── 03_ai_functions.ipynb        # AI Functions（要約/感情分析/抽出/分類/マスキング/類似度）
├── 04_fund_docs.ipynb           # ファンド目論見書 PDF 解析と検索インデックス構築
├── 05_cortex_analyst.ipynb      # Semantic View 作成と Cortex Analyst（自然言語 to SQL）
├── 06_cortex_search.ipynb       # Cortex Search Service とセマンティック検索
└── 07_cortex_agent.ipynb        # Cortex Agent 作成と Snowflake Intelligence デモ
```

## Snowflake 環境

- **接続名**: `KMOT_AWS1`（アカウント: SFSEAPAC-KMOT_AWS1）
- **ロール**: `ACCOUNTADMIN`
- **データベース**: `SNOWFINANCE_DB`
- **スキーマ**: `DEMO_SCHEMA`
- **ウェアハウス**:
  - `DEMO_WH`（MEDIUM）: 通常処理・AI Functions
  - `COMPUTE_WH`（MEDIUM）: Cortex Search インデックス構築用

## 主なテーブル

| テーブル名 | 説明 |
|---|---|
| `DIM_CUSTOMER` | 顧客マスタ（50名） |
| `DIM_FAMILY` | 家族構成（相続人フラグ付き） |
| `DIM_LIFE_EVENT` | ライフイベント（教育・相続・不動産等） |
| `FACT_PORTFOLIO` | 保有資産明細（含み益・含み損） |
| `FACT_TRANSACTION` | 取引履歴 |
| `DIM_TRUST_PRODUCT` | 信託銀行商品（証券担保ローン・教育信託等） |
| `DIM_PRODUCT_RECOMMENDATION` | 商品推奨ロジック |
| `NEWS_ARTICLES` | マーケットニュース 50件（`IMPORTANCE INT` 1-5） |
| `LOAN_PRODUCT_DOCS` | ローン商品説明書（チャンク分割済み） |
| `ANALYST_REPORTS` | アナリストレポート 30件 |
| `RAW_FUND_DOCS` | AI_PARSE_DOCUMENT 解析結果（Markdown） |
| `FUND_DOC_CHUNKS` | 目論見書チャンク（SPLIT_TEXT_MARKDOWN_HEADER） |

## 主な Snowflake オブジェクト

| 種別 | 名前 | 説明 |
|---|---|---|
| Semantic View | `CUSTOMER_WEALTH_SEMANTIC_VIEW` | 顧客資産の自然言語クエリ |
| Semantic View | `TRUST_PRODUCT_SEMANTIC_VIEW` | 信託商品の自然言語クエリ |
| Cortex Search | `NEWS_SEARCH_SERVICE` | ニュース検索 |
| Cortex Search | `LOAN_DOCS_SEARCH_SERVICE` | ローン商品説明書検索 |
| Cortex Search | `ANALYST_REPORT_SEARCH_SERVICE` | アナリストレポート検索 |
| Cortex Search | `FUND_DOCS_SEARCH_SERVICE` | ファンド目論見書検索 |
| Cortex Agent | `WEALTH_MANAGEMENT_ASSISTANT_AGENT` | 統合AIアシスタント |
| Stage | `FUND_DOCS_STAGE` | 目論見書 PDF 格納用 |

## AI Functions の注意事項

- `AI_SENTIMENT` の返り値: `{"label": "positive"|"negative"|"neutral"|"mixed", "score": ...}`
  - アクセス方法: `:label::VARCHAR`（`:categories[0].name` は**不正解**）
  - ラベルは**英語**（`'positive'`/`'negative'`）。CASE 文でも英語で比較すること
- `AI_PARSE_DOCUMENT` の返り値: `PARSE_JSON(...::VARCHAR)['content']::VARCHAR`
- `SPLIT_TEXT_MARKDOWN_HEADER` → `c.value:header`, `c.value:level`, `c.value:content`, `c.index`
- `CORTEX_MODELS_ALLOWLIST` でモデルを制限可能（本番推奨: `claude-3-5-sonnet,claude-3-5-haiku`）

## セキュリティ設定（02_security.ipynb）

- `CORTEX_ENABLED_CROSS_REGION`: 本番推奨 = `'AWS_US'`、ハンズオン = `'ANY_REGION'`
- Model RBAC: `CALL SNOWFLAKE.MODELS.CORTEX_BASE_MODELS_REFRESH()` → `GRANT APPLICATION ROLE SNOWFLAKE."CORTEX-MODEL-ROLE-<MODEL>" TO ROLE ...`
- Cortex 実行権限: `GRANT DATABASE ROLE SNOWFLAKE.CORTEX_USER TO ROLE <role>`

## Git 運用ルール

- **コミットメッセージに顧客名・企業名を含めない**（公開リポジトリのため）
- ファイル内容への言及は問題ないが、コミットメッセージはジェネリックな表現を使うこと
- `docs/` フォルダの PDF ファイルは `.gitignore` に追加を検討すること（著作権に注意）

## デモシナリオ

```
顧客: 山田太郎様（C001、68歳・元上場企業役員・預かり資産8億円）
相談: 「孫の海外留学費用2,000万円のためにトヨタ株(7203)を売りたい」

AIの提案フロー:
  1. トヨタ株の含み益 → 売却時の税負担を試算
  2. 証券担保ローンの活用 → 株を売らずに資金調達
  3. ファンド目論見書検索 → 分散投資・代替案の提案材料
  4. 教育資金贈与信託 → 非課税での孫への資金移転
```
