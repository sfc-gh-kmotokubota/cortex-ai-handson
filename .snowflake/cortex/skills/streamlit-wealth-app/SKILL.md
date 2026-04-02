---
name: streamlit-wealth-app
description: "富裕層顧客インテリジェンス Streamlit ダッシュボードの構築・更新。SNOWFINANCE_DB.DEMO_SCHEMA を基盤とした証券営業支援アプリのページ追加・AI 関数組み込みを支援。Triggers: ダッシュボード, Streamlit, ページ追加, 顧客分析, ポートフォリオ, AI分析, ニュース分析, 富裕層, streamlit-wealth"
---

# 富裕層顧客インテリジェンス — SiS ダッシュボードビルダー

Streamlit in Snowflake アプリ `streamlit_app/` を Workspace 上で構築・更新するスキル。

---

## データ環境

| 項目 | 値 |
|------|-----|
| データベース | `SNOWFINANCE_DB` |
| スキーマ | `DEMO_SCHEMA` |
| 通常ウェアハウス | `DEMO_WH` |
| Cortex Search 用 WH | `COMPUTE_WH` |

### 主要テーブル

| テーブル | 説明 |
|---------|------|
| `DIM_CUSTOMER` | 富裕層顧客マスタ 50名 |
| `FACT_PORTFOLIO` | 保有銘柄・時価・損益 |
| `DIM_LIFE_EVENT` | ライフイベント履歴 |
| `DIM_FAMILY` | 家族構成 |
| `NEWS_ARTICLES` | 関連ニュース（`IMPORTANCE` INT 1-5） |
| `ANALYST_REPORTS` | アナリストレポート |
| `FUND_DOC_CHUNKS` | 投資信託資料チャンク |

### セマンティックビュー / Cortex Search

| オブジェクト | 用途 |
|-------------|------|
| `CUSTOMER_WEALTH_SEMANTIC_VIEW` | 顧客資産 Semantic View |
| `TRUST_PRODUCT_SEMANTIC_VIEW` | 信託商品 Semantic View |
| `NEWS_SEARCH_SERVICE` | ニュース全文検索 |
| `LOAN_DOCS_SEARCH_SERVICE` | ローン資料検索 |
| `ANALYST_REPORT_SEARCH_SERVICE` | アナリストレポート検索 |
| `FUND_DOCS_SEARCH_SERVICE` | ファンド資料検索 |

---

## アプリ構成

```
streamlit_app/
├── main.py                        # ホームページ・機能一覧
├── environment.yml                # 依存パッケージ定義
├── .streamlit/                    # Streamlit 設定
└── pages/
    ├── 1_📊_顧客ダッシュボード.py   # 顧客 KPI・リスク分布・ライフイベント
    ├── 2_💰_ポートフォリオ分析.py   # 資産配分・銘柄損益ランキング
    ├── 3_🤖_AI分析.py              # AI_COMPLETE / AI_SUMMARIZE / AI_SENTIMENT
    └── 4_📰_ニュース分析.py         # ニュース重要度・感情分析・銘柄別トレンド
```

---

## ワークフロー

```
Step 1: ソースコード探索 & 状況把握
    ↓
Step 2: 新規 or 更新を確認（ユーザーに確認）
    ↓
Step 3: コード生成・編集
    ↓
Step 4: デプロイ & 動作確認
```

### Step 1: ソースコード探索

```sql
-- 既存アプリ確認
SHOW STREAMLIT IN SCHEMA SNOWFINANCE_DB.DEMO_SCHEMA;

-- 既存アプリの詳細（ある場合）
DESCRIBE STREAMLIT SNOWFINANCE_DB.DEMO_SCHEMA.<アプリ名>;
```

Workspace 上では `streamlit_app/` ディレクトリのソースを直接確認する。

### Step 2: 新規 or 更新を確認

⚠️ **必ずユーザーに確認してから進む**

| ケース | 対応 |
|--------|------|
| 既存アプリに新ページ追加 | `pages/` に新ファイルを作成 |
| 既存ページの修正 | 対象ファイルを直接編集 |
| 新規アプリのデプロイ | `CREATE STREAMLIT` SQL を実行 |

### Step 3: コード生成・編集

#### 新規ページ追加

ファイル名規則: `pages/<番号>_<絵文字>_<名前>.py`

例: `pages/5_📈_マーケット分析.py`

#### 必須パターン（SiS 固有）

```python
from snowflake.snowpark.context import get_active_session

@st.cache_resource
def get_session():
    return get_active_session()

session = get_session()

@st.cache_data(ttl=300)
def get_data():
    return session.sql("SELECT ...").to_pandas()
```

#### Cortex AI 関数の利用

```python
# AI_COMPLETE — テキスト生成・アドバイス
session.sql(f"""
    SELECT SNOWFLAKE.CORTEX.AI_COMPLETE(
        'claude-3-5-sonnet',
        $${prompt}$$
    ) AS RESULT
""").to_pandas()

# AI_SENTIMENT — 感情分析（戻り値: {label, score}）
session.sql("""
    SELECT
        SNOWFLAKE.CORTEX.AI_SENTIMENT(CONTENT):label::VARCHAR AS SENTIMENT_LABEL,
        SNOWFLAKE.CORTEX.AI_SENTIMENT(CONTENT):score::FLOAT   AS SENTIMENT_SCORE
    FROM SNOWFINANCE_DB.DEMO_SCHEMA.NEWS_ARTICLES
""").to_pandas()

# AI_SUMMARIZE — テキスト要約
session.sql(f"""
    SELECT SNOWFLAKE.CORTEX.AI_SUMMARIZE($${text}$$) AS SUMMARY
""").to_pandas()
```

> ⚠️ `AI_SENTIMENT` の戻り値は `:categories[0].name` ではなく `:label::VARCHAR`

#### IMPORTANCE フィールドについて

`NEWS_ARTICLES.IMPORTANCE` は **INT 型（1-5）**。  
文字列（'高'/'中'/'低'）ではないので CASE 文に注意。

```sql
-- 正しい使い方
WHERE IMPORTANCE >= 3

-- 誤り（文字列比較は動作しない）
WHERE IMPORTANCE = '高'
```

#### カラーパレット（推奨）

```python
COLORS = {
    'primary':   '#29B5E8',   # Snowflake Blue
    'secondary': '#11567F',
    'accent':    '#F5B800',
    'positive':  '#10B981',   # 含み益・ポジティブ
    'negative':  '#EF4444',   # 含み損・ネガティブ
    'neutral':   '#6B7280',
}
```

### Step 4: デプロイ

#### Workspace → ステージ → CREATE STREAMLIT（推奨）

```sql
-- ステージにソースをアップロード後
CREATE OR REPLACE STREAMLIT SNOWFINANCE_DB.DEMO_SCHEMA.WEALTH_DASHBOARD
    ROOT_LOCATION = '@SNOWFINANCE_DB.DEMO_SCHEMA.STREAMLIT_STAGE/streamlit_app'
    MAIN_FILE = 'main.py'
    QUERY_WAREHOUSE = 'DEMO_WH'
    COMMENT = '富裕層顧客インテリジェンス ダッシュボード';
```

#### Git 経由でデプロイ

Git Repository Object `cortex_ai_handson` が設定済みの場合:

```sql
CREATE OR REPLACE STREAMLIT SNOWFINANCE_DB.DEMO_SCHEMA.WEALTH_DASHBOARD
    ROOT_LOCATION = '@SNOWFINANCE_DB.DEMO_SCHEMA.cortex_ai_handson/branches/main/streamlit_app'
    MAIN_FILE = 'main.py'
    QUERY_WAREHOUSE = 'DEMO_WH';
```

---

## 停止ポイント

- ⚠️ **Step 2**: 新規 or 更新をユーザーに確認する前に進まない
- ⚠️ **Step 3**: コードを編集する前にユーザーに方針を提示して承認を得る
- ⚠️ デプロイ前に `SHOW STREAMLIT` で重複がないか確認する
