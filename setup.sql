-- ============================================================================
-- 証券営業インテリジェンス デモ セットアップSQL（汎用版）
-- Part 1: DDL（テーブル定義）& マスタデータ
-- ============================================================================
-- Database: SNOWFINANCE_DB
-- Schema: DEMO_SCHEMA
-- 使用企業: プレミアム証券、プレミアム信託銀行（架空）
-- ============================================================================

-- ============================================================================
-- 0. Snowflake Workspace 用 GitHub リポジトリ連携
--    ※ Snowsight のワークシートで最初に実行してください
--    ※ ACCOUNTADMIN 権限が必要です
-- ============================================================================

USE ROLE ACCOUNTADMIN;

-- ユーザー個人のデータベースに切り替え（Workspace のデフォルト）
SET my_db = 'USER$' || CURRENT_USER();
USE DATABASE IDENTIFIER($my_db);

-- GitHub との API 統合を作成
CREATE OR REPLACE API INTEGRATION git_api_integration
    API_PROVIDER = git_https_api
    API_ALLOWED_PREFIXES = ('https://github.com/kmotokubota/')
    ENABLED = TRUE;

-- 登録確認
SHOW GIT REPOSITORIES;

-- ============================================================================
-- 1. データベース・スキーマ・ウェアハウス作成
-- ============================================================================

USE ROLE ACCOUNTADMIN;
CREATE DATABASE IF NOT EXISTS SNOWFINANCE_DB;
USE DATABASE SNOWFINANCE_DB;

CREATE SCHEMA IF NOT EXISTS DEMO_SCHEMA;
USE SCHEMA DEMO_SCHEMA;

CREATE WAREHOUSE IF NOT EXISTS DEMO_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE;

USE WAREHOUSE DEMO_WH;

-- クロスリージョン推論
ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';

-- ============================================================================
-- 2. Cortex Analyst 1: 顧客資産管理DB - テーブル定義
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 2.1 顧客マスタ (DIM_CUSTOMER) - 100人
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_CUSTOMER (
    CUSTOMER_ID VARCHAR(20) PRIMARY KEY,
    CUSTOMER_NAME VARCHAR(100) NOT NULL,
    CUSTOMER_NAME_KANA VARCHAR(100),
    AGE INT,
    GENDER VARCHAR(10),
    BIRTH_DATE DATE,
    OCCUPATION VARCHAR(100),
    COMPANY_NAME VARCHAR(200),
    POSITION VARCHAR(100),
    PREFECTURE VARCHAR(50),
    CITY VARCHAR(100),
    ANNUAL_INCOME_BAND VARCHAR(50),
    TOTAL_ASSETS DECIMAL(18,0),
    LIQUID_ASSETS DECIMAL(18,0),
    RISK_TOLERANCE VARCHAR(30),
    INVESTMENT_PURPOSE VARCHAR(50),
    INVESTMENT_EXPERIENCE_YEARS INT,
    SEGMENT VARCHAR(50),
    RM_ID VARCHAR(20),
    RM_NAME VARCHAR(100),
    ACCOUNT_OPEN_DATE DATE,
    LAST_CONTACT_DATE DATE,
    HAS_NISA BOOLEAN DEFAULT FALSE,
    HAS_IDECO BOOLEAN DEFAULT FALSE,
    HAS_TRUST_ACCOUNT BOOLEAN DEFAULT FALSE,
    NOTES TEXT,
    CREATED_AT TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_AT TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

COMMENT ON TABLE DIM_CUSTOMER IS '顧客マスタテーブル。富裕層を中心とした顧客の属性情報を管理';

-- ----------------------------------------------------------------------------
-- 2.2 家族構成 (DIM_FAMILY)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_FAMILY (
    FAMILY_ID VARCHAR(20) PRIMARY KEY,
    CUSTOMER_ID VARCHAR(20) NOT NULL,
    RELATIONSHIP VARCHAR(30) NOT NULL,
    FAMILY_NAME VARCHAR(100),
    FAMILY_AGE INT,
    FAMILY_OCCUPATION VARCHAR(100),
    IS_HEIR BOOLEAN DEFAULT FALSE,
    HEIR_PRIORITY INT,
    NOTES TEXT,
    CREATED_AT TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    FOREIGN KEY (CUSTOMER_ID) REFERENCES DIM_CUSTOMER(CUSTOMER_ID)
);

COMMENT ON TABLE DIM_FAMILY IS '顧客の家族構成。相続対策の提案に使用';

-- ----------------------------------------------------------------------------
-- 2.3 ライフイベント (DIM_LIFE_EVENT)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_LIFE_EVENT (
    EVENT_ID VARCHAR(20) PRIMARY KEY,
    CUSTOMER_ID VARCHAR(20) NOT NULL,
    EVENT_TYPE VARCHAR(50) NOT NULL,
    EVENT_DETAIL TEXT,
    EXPECTED_DATE DATE,
    ESTIMATED_AMOUNT DECIMAL(18,0),
    URGENCY VARCHAR(20),
    STATUS VARCHAR(30),
    RELATED_FAMILY_ID VARCHAR(20),
    CREATED_DATE DATE,
    UPDATED_DATE DATE,
    NOTES TEXT,
    FOREIGN KEY (CUSTOMER_ID) REFERENCES DIM_CUSTOMER(CUSTOMER_ID)
);

COMMENT ON TABLE DIM_LIFE_EVENT IS '顧客のライフイベント（教育、相続、不動産購入など）';

-- ----------------------------------------------------------------------------
-- 2.4 ポートフォリオ (FACT_PORTFOLIO)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE FACT_PORTFOLIO (
    PORTFOLIO_ID VARCHAR(20) PRIMARY KEY,
    CUSTOMER_ID VARCHAR(20) NOT NULL,
    ASSET_CLASS VARCHAR(50) NOT NULL,
    SECURITY_CODE VARCHAR(20),
    SECURITY_NAME VARCHAR(200) NOT NULL,
    QUANTITY DECIMAL(18,4),
    ACQUISITION_PRICE DECIMAL(18,4),
    ACQUISITION_DATE DATE,
    CURRENT_PRICE DECIMAL(18,4),
    MARKET_VALUE DECIMAL(18,0),
    UNREALIZED_GAIN DECIMAL(18,0),
    UNREALIZED_GAIN_PCT DECIMAL(10,2),
    ACCOUNT_TYPE VARCHAR(30),
    CURRENCY VARCHAR(10) DEFAULT 'JPY',
    AS_OF_DATE DATE,
    FOREIGN KEY (CUSTOMER_ID) REFERENCES DIM_CUSTOMER(CUSTOMER_ID)
);

COMMENT ON TABLE FACT_PORTFOLIO IS '顧客のポートフォリオ（保有資産明細）';

-- ----------------------------------------------------------------------------
-- 2.5 取引履歴 (FACT_TRANSACTION) - 150件
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE FACT_TRANSACTION (
    TRANSACTION_ID VARCHAR(20) PRIMARY KEY,
    CUSTOMER_ID VARCHAR(20) NOT NULL,
    TRANSACTION_DATE DATE NOT NULL,
    SETTLEMENT_DATE DATE,
    TRANSACTION_TYPE VARCHAR(20) NOT NULL,
    ASSET_CLASS VARCHAR(50),
    SECURITY_CODE VARCHAR(20),
    SECURITY_NAME VARCHAR(200),
    QUANTITY DECIMAL(18,4),
    PRICE DECIMAL(18,4),
    AMOUNT DECIMAL(18,0),
    FEE DECIMAL(18,0),
    TAX DECIMAL(18,0),
    NET_AMOUNT DECIMAL(18,0),
    ACCOUNT_TYPE VARCHAR(30),
    ORDER_CHANNEL VARCHAR(30),
    RM_ID VARCHAR(20),
    NOTES TEXT,
    FOREIGN KEY (CUSTOMER_ID) REFERENCES DIM_CUSTOMER(CUSTOMER_ID)
);

COMMENT ON TABLE FACT_TRANSACTION IS '取引履歴（売買・入出金等）';

-- ============================================================================
-- 3. Cortex Analyst 2: 信託銀行商品DB - テーブル定義
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 3.1 信託商品マスタ (DIM_TRUST_PRODUCT)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_TRUST_PRODUCT (
    PRODUCT_ID VARCHAR(20) PRIMARY KEY,
    PRODUCT_NAME VARCHAR(200) NOT NULL,
    PRODUCT_NAME_EN VARCHAR(200),
    PRODUCT_CATEGORY VARCHAR(50) NOT NULL,
    PRODUCT_SUBCATEGORY VARCHAR(50),
    DESCRIPTION TEXT,
    MIN_AMOUNT DECIMAL(18,0),
    MAX_AMOUNT DECIMAL(18,0),
    INTEREST_RATE_MIN DECIMAL(5,2),
    INTEREST_RATE_MAX DECIMAL(5,2),
    TERM_MIN_MONTHS INT,
    TERM_MAX_MONTHS INT,
    ELIGIBLE_SEGMENT VARCHAR(100),
    ELIGIBLE_ASSETS_MIN DECIMAL(18,0),
    TAX_BENEFIT TEXT,
    RISKS TEXT,
    IS_ACTIVE BOOLEAN DEFAULT TRUE,
    LAUNCH_DATE DATE,
    PROVIDER VARCHAR(100) DEFAULT 'プレミアム信託銀行'
);

COMMENT ON TABLE DIM_TRUST_PRODUCT IS '信託銀行の商品マスタ';

-- ----------------------------------------------------------------------------
-- 3.2 商品推奨ロジック (DIM_PRODUCT_RECOMMENDATION)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE DIM_PRODUCT_RECOMMENDATION (
    RECOMMENDATION_ID VARCHAR(20) PRIMARY KEY,
    PRODUCT_ID VARCHAR(20) NOT NULL,
    TARGET_LIFE_EVENT VARCHAR(50),
    TARGET_AGE_MIN INT,
    TARGET_AGE_MAX INT,
    TARGET_ASSETS_MIN DECIMAL(18,0),
    TARGET_ASSETS_MAX DECIMAL(18,0),
    TARGET_RISK_TOLERANCE VARCHAR(30),
    TARGET_SEGMENT VARCHAR(50),
    RECOMMENDATION_REASON TEXT,
    BENEFIT_DESCRIPTION TEXT,
    COMPARISON_WITH_ALTERNATIVE TEXT,
    PRIORITY INT DEFAULT 5,
    IS_ACTIVE BOOLEAN DEFAULT TRUE,
    FOREIGN KEY (PRODUCT_ID) REFERENCES DIM_TRUST_PRODUCT(PRODUCT_ID)
);

COMMENT ON TABLE DIM_PRODUCT_RECOMMENDATION IS '商品推奨ロジック（どの顧客にどの商品を提案すべきか）';

-- ============================================================================
-- 4. Cortex Search用テーブル定義
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 4.1 マーケットニュース (NEWS_ARTICLES)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE NEWS_ARTICLES (
    NEWS_ID VARCHAR(20) PRIMARY KEY,
    PUBLISH_DATE DATE NOT NULL,
    PUBLISH_DATETIME TIMESTAMP,
    SOURCE VARCHAR(100),
    CATEGORY VARCHAR(50),
    TITLE VARCHAR(500) NOT NULL,
    CONTENT TEXT NOT NULL,
    SUMMARY TEXT,
    RELATED_SECURITIES VARCHAR(500),
    SENTIMENT VARCHAR(20),
    IMPORTANCE VARCHAR(10),
    TAGS VARCHAR(500)
);

COMMENT ON TABLE NEWS_ARTICLES IS 'マーケットニュース・税制改正ニュースなど';

-- ----------------------------------------------------------------------------
-- 4.2 ローン商品説明書 (LOAN_PRODUCT_DOCS)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE LOAN_PRODUCT_DOCS (
    DOC_ID VARCHAR(20) PRIMARY KEY,
    PRODUCT_ID VARCHAR(20),
    DOC_TYPE VARCHAR(50),
    SECTION VARCHAR(100),
    TITLE VARCHAR(200),
    CONTENT TEXT NOT NULL,
    PAGE_NUMBER INT,
    CHUNK_INDEX INT,
    CREATED_AT TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

COMMENT ON TABLE LOAN_PRODUCT_DOCS IS 'ローン商品の説明書（チャンク分割済み）';

-- ----------------------------------------------------------------------------
-- 4.3 アナリストレポート (ANALYST_REPORTS)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE TABLE ANALYST_REPORTS (
    REPORT_ID VARCHAR(20) PRIMARY KEY,
    PUBLISH_DATE DATE NOT NULL,
    SECURITY_CODE VARCHAR(20),
    SECURITY_NAME VARCHAR(200),
    ANALYST_NAME VARCHAR(100),
    ANALYST_TEAM VARCHAR(100),
    RATING VARCHAR(20),
    PREVIOUS_RATING VARCHAR(20),
    TARGET_PRICE DECIMAL(18,0),
    PREVIOUS_TARGET_PRICE DECIMAL(18,0),
    CURRENT_PRICE DECIMAL(18,0),
    UPSIDE_PCT DECIMAL(10,2),
    REPORT_TITLE VARCHAR(500),
    EXECUTIVE_SUMMARY TEXT,
    INVESTMENT_THESIS TEXT,
    KEY_RISKS TEXT,
    EARNINGS_FORECAST TEXT,
    CONTENT TEXT
);

COMMENT ON TABLE ANALYST_REPORTS IS '証券アナリストレポート';

-- ============================================================================
-- 5. 相続税試算用ビュー
-- ============================================================================

CREATE OR REPLACE VIEW V_INHERITANCE_TAX_ESTIMATE AS
SELECT 
    c.CUSTOMER_ID,
    c.CUSTOMER_NAME,
    c.AGE,
    c.TOTAL_ASSETS,
    -- 法定相続人数をカウント
    COALESCE(heir_count.NUM_HEIRS, 1) AS NUM_HEIRS,
    -- 基礎控除額 = 3000万円 + 600万円 × 法定相続人数
    30000000 + (6000000 * COALESCE(heir_count.NUM_HEIRS, 1)) AS BASIC_DEDUCTION,
    -- 課税遺産総額
    GREATEST(c.TOTAL_ASSETS - (30000000 + (6000000 * COALESCE(heir_count.NUM_HEIRS, 1))), 0) AS TAXABLE_ESTATE,
    -- 相続税概算（簡易計算：累進税率を適用）
    CASE 
        WHEN c.TOTAL_ASSETS - (30000000 + (6000000 * COALESCE(heir_count.NUM_HEIRS, 1))) <= 0 THEN 0
        WHEN c.TOTAL_ASSETS - (30000000 + (6000000 * COALESCE(heir_count.NUM_HEIRS, 1))) <= 10000000 THEN 
            (c.TOTAL_ASSETS - (30000000 + (6000000 * COALESCE(heir_count.NUM_HEIRS, 1)))) * 0.10
        WHEN c.TOTAL_ASSETS - (30000000 + (6000000 * COALESCE(heir_count.NUM_HEIRS, 1))) <= 30000000 THEN 
            1000000 + ((c.TOTAL_ASSETS - (30000000 + (6000000 * COALESCE(heir_count.NUM_HEIRS, 1))) - 10000000) * 0.15)
        WHEN c.TOTAL_ASSETS - (30000000 + (6000000 * COALESCE(heir_count.NUM_HEIRS, 1))) <= 50000000 THEN 
            1000000 + 3000000 + ((c.TOTAL_ASSETS - (30000000 + (6000000 * COALESCE(heir_count.NUM_HEIRS, 1))) - 30000000) * 0.20)
        WHEN c.TOTAL_ASSETS - (30000000 + (6000000 * COALESCE(heir_count.NUM_HEIRS, 1))) <= 100000000 THEN 
            1000000 + 3000000 + 4000000 + ((c.TOTAL_ASSETS - (30000000 + (6000000 * COALESCE(heir_count.NUM_HEIRS, 1))) - 50000000) * 0.30)
        WHEN c.TOTAL_ASSETS - (30000000 + (6000000 * COALESCE(heir_count.NUM_HEIRS, 1))) <= 200000000 THEN 
            1000000 + 3000000 + 4000000 + 15000000 + ((c.TOTAL_ASSETS - (30000000 + (6000000 * COALESCE(heir_count.NUM_HEIRS, 1))) - 100000000) * 0.40)
        WHEN c.TOTAL_ASSETS - (30000000 + (6000000 * COALESCE(heir_count.NUM_HEIRS, 1))) <= 300000000 THEN 
            1000000 + 3000000 + 4000000 + 15000000 + 40000000 + ((c.TOTAL_ASSETS - (30000000 + (6000000 * COALESCE(heir_count.NUM_HEIRS, 1))) - 200000000) * 0.45)
        WHEN c.TOTAL_ASSETS - (30000000 + (6000000 * COALESCE(heir_count.NUM_HEIRS, 1))) <= 600000000 THEN 
            1000000 + 3000000 + 4000000 + 15000000 + 40000000 + 45000000 + ((c.TOTAL_ASSETS - (30000000 + (6000000 * COALESCE(heir_count.NUM_HEIRS, 1))) - 300000000) * 0.50)
        ELSE 
            1000000 + 3000000 + 4000000 + 15000000 + 40000000 + 45000000 + 150000000 + ((c.TOTAL_ASSETS - (30000000 + (6000000 * COALESCE(heir_count.NUM_HEIRS, 1))) - 600000000) * 0.55)
    END AS ESTIMATED_TAX,
    -- 実効税率
    CASE 
        WHEN c.TOTAL_ASSETS > 0 THEN 
            ROUND(CASE 
                WHEN c.TOTAL_ASSETS - (30000000 + (6000000 * COALESCE(heir_count.NUM_HEIRS, 1))) <= 0 THEN 0
                ELSE (c.TOTAL_ASSETS - (30000000 + (6000000 * COALESCE(heir_count.NUM_HEIRS, 1)))) * 0.30
            END / c.TOTAL_ASSETS * 100, 2)
        ELSE 0
    END AS EFFECTIVE_TAX_RATE_PCT
FROM DIM_CUSTOMER c
LEFT JOIN (
    SELECT CUSTOMER_ID, COUNT(*) AS NUM_HEIRS
    FROM DIM_FAMILY
    WHERE IS_HEIR = TRUE
    GROUP BY CUSTOMER_ID
) heir_count ON c.CUSTOMER_ID = heir_count.CUSTOMER_ID
WHERE c.TOTAL_ASSETS > 0;

COMMENT ON VIEW V_INHERITANCE_TAX_ESTIMATE IS '相続税概算ビュー（簡易計算）';

-- ============================================================================
-- 6. 分析用集計ビュー
-- ============================================================================

-- ポートフォリオサマリービュー
CREATE OR REPLACE VIEW V_PORTFOLIO_SUMMARY AS
SELECT 
    c.CUSTOMER_ID,
    c.CUSTOMER_NAME,
    c.SEGMENT,
    c.TOTAL_ASSETS,
    p.ASSET_CLASS,
    SUM(p.MARKET_VALUE) AS ASSET_CLASS_VALUE,
    ROUND(SUM(p.MARKET_VALUE) / c.TOTAL_ASSETS * 100, 2) AS ALLOCATION_PCT,
    SUM(p.UNREALIZED_GAIN) AS TOTAL_UNREALIZED_GAIN,
    ROUND(SUM(p.UNREALIZED_GAIN) / NULLIF(SUM(p.MARKET_VALUE - p.UNREALIZED_GAIN), 0) * 100, 2) AS RETURN_PCT
FROM DIM_CUSTOMER c
JOIN FACT_PORTFOLIO p ON c.CUSTOMER_ID = p.CUSTOMER_ID
GROUP BY c.CUSTOMER_ID, c.CUSTOMER_NAME, c.SEGMENT, c.TOTAL_ASSETS, p.ASSET_CLASS;

COMMENT ON VIEW V_PORTFOLIO_SUMMARY IS 'ポートフォリオ資産クラス別サマリー';

-- 顧客360度ビュー
CREATE OR REPLACE VIEW V_CUSTOMER_360 AS
SELECT 
    c.*,
    -- 家族情報
    family_agg.NUM_FAMILY_MEMBERS,
    family_agg.NUM_HEIRS,
    family_agg.FAMILY_SUMMARY,
    -- ライフイベント
    event_agg.PENDING_EVENTS,
    event_agg.TOTAL_EVENT_AMOUNT,
    event_agg.NEXT_EVENT,
    -- ポートフォリオ
    port_agg.NUM_HOLDINGS,
    port_agg.TOTAL_MARKET_VALUE,
    port_agg.TOTAL_UNREALIZED_GAIN,
    port_agg.TOP_HOLDING,
    -- 取引
    txn_agg.NUM_TRANSACTIONS_YTD,
    txn_agg.TOTAL_VOLUME_YTD,
    txn_agg.LAST_TRANSACTION_DATE,
    -- 相続税試算
    tax.ESTIMATED_TAX AS ESTIMATED_INHERITANCE_TAX,
    tax.EFFECTIVE_TAX_RATE_PCT
FROM DIM_CUSTOMER c
LEFT JOIN (
    SELECT 
        CUSTOMER_ID,
        COUNT(*) AS NUM_FAMILY_MEMBERS,
        SUM(CASE WHEN IS_HEIR THEN 1 ELSE 0 END) AS NUM_HEIRS,
        LISTAGG(RELATIONSHIP || '(' || FAMILY_NAME || ')', ', ') AS FAMILY_SUMMARY
    FROM DIM_FAMILY
    GROUP BY CUSTOMER_ID
) family_agg ON c.CUSTOMER_ID = family_agg.CUSTOMER_ID
LEFT JOIN (
    SELECT 
        CUSTOMER_ID,
        COUNT(*) AS PENDING_EVENTS,
        SUM(ESTIMATED_AMOUNT) AS TOTAL_EVENT_AMOUNT,
        MIN(EVENT_TYPE || ': ' || TO_VARCHAR(EXPECTED_DATE, 'YYYY-MM')) AS NEXT_EVENT
    FROM DIM_LIFE_EVENT
    WHERE STATUS IN ('相談中', '計画中', '予定')
    GROUP BY CUSTOMER_ID
) event_agg ON c.CUSTOMER_ID = event_agg.CUSTOMER_ID
LEFT JOIN (
    SELECT 
        CUSTOMER_ID,
        COUNT(*) AS NUM_HOLDINGS,
        SUM(MARKET_VALUE) AS TOTAL_MARKET_VALUE,
        SUM(UNREALIZED_GAIN) AS TOTAL_UNREALIZED_GAIN,
        MAX_BY(SECURITY_NAME, MARKET_VALUE) AS TOP_HOLDING
    FROM FACT_PORTFOLIO
    GROUP BY CUSTOMER_ID
) port_agg ON c.CUSTOMER_ID = port_agg.CUSTOMER_ID
LEFT JOIN (
    SELECT 
        CUSTOMER_ID,
        COUNT(*) AS NUM_TRANSACTIONS_YTD,
        SUM(AMOUNT) AS TOTAL_VOLUME_YTD,
        MAX(TRANSACTION_DATE) AS LAST_TRANSACTION_DATE
    FROM FACT_TRANSACTION
    WHERE TRANSACTION_DATE >= DATE_TRUNC('YEAR', CURRENT_DATE())
    GROUP BY CUSTOMER_ID
) txn_agg ON c.CUSTOMER_ID = txn_agg.CUSTOMER_ID
LEFT JOIN V_INHERITANCE_TAX_ESTIMATE tax ON c.CUSTOMER_ID = tax.CUSTOMER_ID;

COMMENT ON VIEW V_CUSTOMER_360 IS '顧客360度ビュー（全情報統合）';

SELECT 'Part 1: DDL completed successfully!' AS STATUS;

-- ============================================================================
-- 証券営業インテリジェンス デモ セットアップSQL（汎用版）
-- Part 2: 顧客データ（100人）& 家族・ライフイベント
-- ============================================================================

USE DATABASE SNOWFINANCE_DB;
USE SCHEMA DEMO_SCHEMA;
USE WAREHOUSE DEMO_WH;

-- ============================================================================
-- 1. 主要顧客データ（デモ用キーパーソン）- 30人
-- ============================================================================

INSERT INTO DIM_CUSTOMER VALUES
-- デモの主人公：山田太郎様（68歳、元上場企業役員）
('C001', '山田太郎', 'ヤマダタロウ', 68, '男性', '1957-03-15', '元上場企業役員', '大手電機メーカー', '元取締役', '東京都', '港区', '2000万円以上', 800000000, 500000000, '保守的', '資産保全', 40, 'プライベートバンク', 'RM001', '田中誠一', '2005-04-01', '2025-01-08', TRUE, FALSE, TRUE, '相続対策に関心あり', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()),

-- プライベートバンク顧客（10人）
('C002', '鈴木一郎', 'スズキイチロウ', 72, '男性', '1953-08-22', 'オーナー経営者', '鈴木商事株式会社', '代表取締役会長', '東京都', '世田谷区', '5000万円以上', 1500000000, 800000000, '保守的', '事業承継', 50, 'プライベートバンク', 'RM001', '田中誠一', '2000-01-15', '2025-01-10', TRUE, FALSE, TRUE, '事業承継を検討中', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()),
('C003', '佐藤花子', 'サトウハナコ', 65, '女性', '1960-05-10', '資産家', NULL, NULL, '神奈川県', '横浜市', '2000万円以上', 600000000, 400000000, 'やや保守的', '資産保全', 30, 'プライベートバンク', 'RM002', '山本美咲', '2010-06-01', '2025-01-05', TRUE, TRUE, TRUE, '夫の遺産を相続、子供2人', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()),
('C004', '高橋健一', 'タカハシケンイチ', 58, '男性', '1967-11-03', '医療法人理事長', '高橋クリニック', '理事長', '東京都', '新宿区', '5000万円以上', 1200000000, 600000000, 'やや積極的', '資産形成', 25, 'プライベートバンク', 'RM001', '田中誠一', '2008-03-01', '2025-01-12', TRUE, TRUE, TRUE, 'クリニック経営、後継者育成中', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()),
('C005', '伊藤美智子', 'イトウミチコ', 70, '女性', '1955-02-28', '不動産オーナー', NULL, NULL, '東京都', '渋谷区', '2000万円以上', 900000000, 300000000, '保守的', '資産保全', 35, 'プライベートバンク', 'RM002', '山本美咲', '2003-09-01', '2024-12-20', TRUE, FALSE, TRUE, '都内に賃貸物件5棟保有', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()),
('C006', '渡辺正樹', 'ワタナベマサキ', 62, '男性', '1963-07-18', 'ベンチャー創業者', 'テックイノベーション株式会社', '創業者・顧問', '東京都', '千代田区', '5000万円以上', 2000000000, 1200000000, '積極的', '資産形成', 20, 'プライベートバンク', 'RM003', '佐々木大輔', '2015-01-01', '2025-01-15', TRUE, TRUE, FALSE, 'IPO後の資産運用、慈善活動に関心', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()),
('C007', '中村雄太', 'ナカムラユウタ', 55, '男性', '1970-04-05', '外資系金融MD', 'グローバル投資銀行', 'マネージングディレクター', '東京都', '港区', '5000万円以上', 500000000, 350000000, '積極的', '資産形成', 30, 'プライベートバンク', 'RM003', '佐々木大輔', '2012-05-01', '2025-01-08', TRUE, TRUE, FALSE, '海外赴任経験あり、グローバル分散志向', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()),
('C008', '小林京子', 'コバヤシキョウコ', 68, '女性', '1957-09-12', '芸術家', NULL, NULL, '京都府', '京都市', '1000万円以上', 400000000, 250000000, '保守的', '資産保全', 25, 'プライベートバンク', 'RM004', '鈴木健太', '2007-11-01', '2024-12-15', TRUE, FALSE, TRUE, '美術品コレクター、文化財寄贈を検討', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()),
('C009', '加藤誠司', 'カトウセイジ', 75, '男性', '1950-01-20', '元大学教授', '国立大学', '名誉教授', '埼玉県', 'さいたま市', '1000万円以上', 350000000, 200000000, '保守的', '資産保全', 40, 'プライベートバンク', 'RM004', '鈴木健太', '2002-04-01', '2024-12-28', TRUE, TRUE, TRUE, '学術基金への寄付を検討', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()),
('C010', '吉田幸子', 'ヨシダサチコ', 60, '女性', '1965-06-25', '会社役員', '大手商社', '常務取締役', '東京都', '文京区', '2000万円以上', 700000000, 450000000, 'やや積極的', '資産形成', 28, 'プライベートバンク', 'RM002', '山本美咲', '2010-08-01', '2025-01-10', TRUE, TRUE, TRUE, 'キャリアウーマン、独身', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()),

-- ゴールド顧客（10人）
('C011', '松本大輔', 'マツモトダイスケ', 52, '男性', '1973-03-08', '中小企業経営者', '松本工業株式会社', '代表取締役', '愛知県', '名古屋市', '1500万円以上', 200000000, 120000000, 'やや積極的', '資産形成', 20, 'ゴールド', 'RM005', '木村洋介', '2015-02-01', '2025-01-05', TRUE, TRUE, FALSE, '製造業、後継者問題あり', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()),
('C012', '井上直美', 'イノウエナオミ', 48, '女性', '1977-08-15', '歯科医師', '井上歯科クリニック', '院長', '大阪府', '大阪市', '1500万円以上', 180000000, 100000000, 'やや積極的', '資産形成', 15, 'ゴールド', 'RM006', '高橋由美', '2018-04-01', '2025-01-12', TRUE, TRUE, FALSE, '開業10年、分院展開を検討', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()),
('C013', '山口健二', 'ヤマグチケンジ', 63, '男性', '1962-12-01', '退職公務員', '中央省庁', '元局長', '千葉県', '千葉市', '1000万円以上', 150000000, 80000000, '保守的', '年金補完', 35, 'ゴールド', 'RM005', '木村洋介', '2020-04-01', '2024-12-20', TRUE, TRUE, TRUE, '退職金運用、安定志向', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()),
('C014', '森田優子', 'モリタユウコ', 55, '女性', '1970-05-20', '薬剤師', '森田薬局', '経営者', '福岡県', '福岡市', '1000万円以上', 120000000, 70000000, 'やや保守的', '資産形成', 20, 'ゴールド', 'RM006', '高橋由美', '2016-07-01', '2025-01-08', TRUE, TRUE, FALSE, '調剤薬局3店舗経営', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()),
('C015', '清水俊介', 'シミズシュンスケ', 45, '男性', '1980-09-30', 'IT企業役員', 'デジタルソリューションズ株式会社', '取締役CTO', '東京都', '品川区', '2000万円以上', 250000000, 180000000, '積極的', '資産形成', 12, 'ゴールド', 'RM007', '中村健一', '2019-01-01', '2025-01-15', TRUE, TRUE, FALSE, 'ストックオプション行使後の運用', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()),
('C016', '藤田恵子', 'フジタケイコ', 58, '女性', '1967-02-14', '専業主婦', NULL, NULL, '兵庫県', '神戸市', '1000万円以上', 180000000, 100000000, '保守的', '資産保全', 25, 'ゴールド', 'RM006', '高橋由美', '2012-03-01', '2024-12-25', TRUE, FALSE, TRUE, '夫は大手企業役員、教育資金に関心', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()),
('C017', '岡田隆志', 'オカダタカシ', 67, '男性', '1958-07-07', '元銀行員', '大手銀行', '元支店長', '広島県', '広島市', '1000万円以上', 130000000, 80000000, '保守的', '年金補完', 40, 'ゴールド', 'RM008', '山田太郎', '2017-05-01', '2025-01-03', TRUE, TRUE, TRUE, '金融知識豊富、慎重派', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()),
('C018', '石井美香', 'イシイミカ', 42, '女性', '1983-11-22', 'コンサルタント', '外資系コンサルティング', 'シニアマネージャー', '東京都', '目黒区', '1500万円以上', 100000000, 70000000, '積極的', '資産形成', 10, 'ゴールド', 'RM007', '中村健一', '2020-08-01', '2025-01-10', TRUE, TRUE, FALSE, '独身、キャリア志向、海外投資に関心', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()),
('C019', '池田正男', 'イケダマサオ', 71, '男性', '1954-04-18', '農業経営者', '池田農園', '代表', '北海道', '札幌市', '1000万円以上', 200000000, 50000000, '保守的', '資産保全', 30, 'ゴールド', 'RM008', '山田太郎', '2008-06-01', '2024-12-18', FALSE, FALSE, TRUE, '農地・不動産中心、現金化相談', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()),
('C020', '西村美紀', 'ニシムラミキ', 50, '女性', '1975-10-05', '税理士', '西村税理士事務所', '所長', '東京都', '中央区', '1500万円以上', 160000000, 100000000, 'やや積極的', '資産形成', 18, 'ゴールド', 'RM007', '中村健一', '2014-09-01', '2025-01-12', TRUE, TRUE, FALSE, '顧問先の富裕層紹介あり', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()),

-- シルバー顧客（10人）
('C021', '原田浩二', 'ハラダコウジ', 38, '男性', '1987-06-12', '会社員', '大手商社', '課長', '東京都', '江東区', '800万円以上', 50000000, 35000000, 'やや積極的', '資産形成', 8, 'シルバー', 'RM009', '佐藤花子', '2021-04-01', '2025-01-08', TRUE, TRUE, FALSE, '共働き、住宅ローンあり', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()),
('C022', '長谷川理恵', 'ハセガワリエ', 35, '女性', '1990-03-25', '医師', '大学病院', '助教', '東京都', '文京区', '1000万円以上', 40000000, 30000000, '積極的', '資産形成', 5, 'シルバー', 'RM009', '佐藤花子', '2022-01-01', '2025-01-10', TRUE, TRUE, FALSE, '研究医、将来は開業希望', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()),
('C023', '村上達也', 'ムラカミタツヤ', 60, '男性', '1965-08-08', '自営業', '村上設計事務所', '代表', '神奈川県', '川崎市', '800万円以上', 80000000, 50000000, 'やや保守的', '老後資金', 25, 'シルバー', 'RM010', '鈴木一郎', '2016-11-01', '2024-12-22', TRUE, TRUE, FALSE, '一級建築士、仕事は徐々に縮小', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()),
('C024', '近藤美穂', 'コンドウミホ', 45, '女性', '1980-01-15', 'フリーランス', NULL, 'Webデザイナー', '東京都', '杉並区', '600万円以上', 30000000, 25000000, 'やや積極的', '資産形成', 10, 'シルバー', 'RM009', '佐藤花子', '2020-05-01', '2025-01-05', TRUE, TRUE, FALSE, '収入は不安定だが貯蓄意識高い', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()),
('C025', '遠藤隆', 'エンドウタカシ', 55, '男性', '1970-12-20', '会社員', '製造業', '部長', '静岡県', '静岡市', '1000万円以上', 70000000, 45000000, 'やや保守的', '老後資金', 20, 'シルバー', 'RM010', '鈴木一郎', '2018-03-01', '2024-12-28', TRUE, TRUE, FALSE, '役職定年間近、セカンドキャリア検討', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()),
('C026', '青木春子', 'アオキハルコ', 68, '女性', '1957-04-03', '年金生活者', NULL, NULL, '神奈川県', '藤沢市', '500万円以上', 60000000, 40000000, '保守的', '年金補完', 30, 'シルバー', 'RM010', '鈴木一郎', '2015-07-01', '2025-01-03', TRUE, FALSE, TRUE, '夫を亡くし一人暮らし', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()),
('C027', '前田康之', 'マエダヤスユキ', 48, '男性', '1977-05-28', '会社員', '金融機関', '課長', '大阪府', '吹田市', '1000万円以上', 55000000, 40000000, 'やや積極的', '資産形成', 15, 'シルバー', 'RM011', '井上直美', '2019-09-01', '2025-01-10', TRUE, TRUE, FALSE, '投資に詳しい、自分で調べるタイプ', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()),
('C028', '小川真理', 'オガワマリ', 40, '女性', '1985-09-10', '公認会計士', '監査法人', 'マネージャー', '東京都', '千代田区', '1200万円以上', 45000000, 35000000, '積極的', '資産形成', 8, 'シルバー', 'RM011', '井上直美', '2021-06-01', '2025-01-12', TRUE, TRUE, FALSE, '数字に強い、ESG投資に関心', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()),
('C029', '川村英樹', 'カワムラヒデキ', 62, '男性', '1963-02-22', '自営業', '川村商店', '店主', '京都府', '宇治市', '600万円以上', 90000000, 30000000, '保守的', '資産保全', 35, 'シルバー', 'RM012', '渡辺正樹', '2010-04-01', '2024-12-15', FALSE, FALSE, TRUE, '老舗茶商、事業継続に悩み', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP()),
('C030', '坂本由紀', 'サカモトユキ', 33, '女性', '1992-07-18', '会社員', 'IT企業', 'エンジニア', '東京都', '渋谷区', '700万円以上', 25000000, 20000000, '積極的', '資産形成', 5, 'シルバー', 'RM012', '渡辺正樹', '2023-01-01', '2025-01-15', TRUE, TRUE, FALSE, 'FIRE志向、積極投資希望', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP());

-- ============================================================================
-- 2. 追加顧客データ（70人）- SQL GENERATOR で一括生成
-- ============================================================================

-- 顧客データ生成用プロシージャ
-- 追加顧客 70名を SQL GENERATOR で一括生成 (C031-C100)
INSERT INTO DIM_CUSTOMER (
    CUSTOMER_ID, CUSTOMER_NAME, AGE, GENDER, OCCUPATION, PREFECTURE,
    ANNUAL_INCOME_BAND, TOTAL_ASSETS, LIQUID_ASSETS, RISK_TOLERANCE,
    INVESTMENT_PURPOSE, SEGMENT, RM_ID, HAS_NISA, HAS_IDECO, HAS_TRUST_ACCOUNT,
    INVESTMENT_EXPERIENCE_YEARS
)
WITH g AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY SEQ4()) AS rn,
        UNIFORM(0, 19, RANDOM()) AS s_idx,
        UNIFORM(0,  9, RANDOM()) AS fn_idx,
        UNIFORM(30, 79, RANDOM()) AS age,
        UNIFORM(0,  1, RANDOM()) AS gd,
        UNIFORM(0, 14, RANDOM()) AS occ_idx,
        UNIFORM(0, 14, RANDOM()) AS pref_idx,
        UNIFORM(0,  3, RANDOM()) AS seg_idx,
        UNIFORM(0,  3, RANDOM()) AS risk_idx,
        UNIFORM(0,  5, RANDOM()) AS purp_idx,
        UNIFORM(0,  5, RANDOM()) AS inc_idx,
        UNIFORM(1, 12, RANDOM()) AS rm_num,
        UNIFORM(0, 99, RANDOM()) AS r_nisa,
        UNIFORM(0, 99, RANDOM()) AS r_ideco,
        UNIFORM(0, 99, RANDOM()) AS r_trust,
        UNIFORM(1, 30, RANDOM()) AS exp_yr,
        UNIFORM(0, 99, RANDOM()) AS asset_pct
    FROM TABLE(GENERATOR(ROWCOUNT => 70))
), seg AS (
    SELECT g.*,
        CASE seg_idx
            WHEN 0 THEN 'プライベートバンク'
            WHEN 1 THEN 'ゴールド'
            WHEN 2 THEN 'シルバー'
            ELSE        'ブロンズ'
        END AS seg_val,
        CASE seg_idx
            WHEN 0 THEN 300000000 + CAST(asset_pct / 100.0 * 1500000000 AS BIGINT)
            WHEN 1 THEN 100000000 + CAST(asset_pct / 100.0 *  200000000 AS BIGINT)
            WHEN 2 THEN  30000000 + CAST(asset_pct / 100.0 *   70000000 AS BIGINT)
            ELSE         10000000 + CAST(asset_pct / 100.0 *   20000000 AS BIGINT)
        END AS ta
    FROM g
)
SELECT
    'C' || LPAD(CAST(rn + 30 AS VARCHAR), 3, '0'),
    CASE s_idx
        WHEN 0 THEN '田中' WHEN 1 THEN '山本' WHEN 2 THEN '中島' WHEN 3 THEN '小林'
        WHEN 4 THEN '加藤' WHEN 5 THEN '吉田' WHEN 6 THEN '山田' WHEN 7 THEN '佐々木'
        WHEN 8 THEN '高橋' WHEN 9 THEN '伊藤' WHEN 10 THEN '渡辺' WHEN 11 THEN '斎藤'
        WHEN 12 THEN '鈴木' WHEN 13 THEN '松本' WHEN 14 THEN '井上' WHEN 15 THEN '木村'
        WHEN 16 THEN '林'  WHEN 17 THEN '清水' WHEN 18 THEN '山口' ELSE '森'
    END ||
    CASE WHEN gd = 0 THEN
        CASE fn_idx WHEN 0 THEN '太郎' WHEN 1 THEN '一郎' WHEN 2 THEN '健太'
            WHEN 3 THEN '翔太' WHEN 4 THEN '大輔' WHEN 5 THEN '拓也'
            WHEN 6 THEN '直樹' WHEN 7 THEN '誠'  WHEN 8 THEN '浩二' ELSE '正樹' END
    ELSE
        CASE fn_idx WHEN 0 THEN '花子' WHEN 1 THEN '美咲' WHEN 2 THEN '由美'
            WHEN 3 THEN '恵子' WHEN 4 THEN '理恵' WHEN 5 THEN '直美'
            WHEN 6 THEN '京子' WHEN 7 THEN '智子' WHEN 8 THEN '美香' ELSE '裕子' END
    END,
    age,
    CASE WHEN gd = 0 THEN '男性' ELSE '女性' END,
    CASE occ_idx
        WHEN 0 THEN '会社員'     WHEN 1 THEN '会社役員'   WHEN 2 THEN '公務員'
        WHEN 3 THEN '医師'       WHEN 4 THEN '弁護士'     WHEN 5 THEN '税理士'
        WHEN 6 THEN '自営業'     WHEN 7 THEN '年金生活者' WHEN 8 THEN '経営者'
        WHEN 9 THEN 'コンサルタント' WHEN 10 THEN '不動産業' WHEN 11 THEN '農業'
        WHEN 12 THEN '教員'      WHEN 13 THEN '薬剤師'    ELSE 'エンジニア'
    END,
    CASE pref_idx
        WHEN 0 THEN '東京都'   WHEN 1 THEN '神奈川県' WHEN 2 THEN '大阪府'
        WHEN 3 THEN '愛知県'   WHEN 4 THEN '埼玉県'   WHEN 5 THEN '千葉県'
        WHEN 6 THEN '兵庫県'   WHEN 7 THEN '北海道'   WHEN 8 THEN '福岡県'
        WHEN 9 THEN '京都府'   WHEN 10 THEN '静岡県'  WHEN 11 THEN '広島県'
        WHEN 12 THEN '茨城県'  WHEN 13 THEN '新潟県'  ELSE '宮城県'
    END,
    CASE inc_idx
        WHEN 0 THEN '500万円以上'  WHEN 1 THEN '800万円以上'  WHEN 2 THEN '1000万円以上'
        WHEN 3 THEN '1500万円以上' WHEN 4 THEN '2000万円以上' ELSE '5000万円以上'
    END,
    ta,
    CAST(ta * (0.4 + asset_pct / 300.0) AS BIGINT),
    CASE risk_idx
        WHEN 0 THEN '保守的' WHEN 1 THEN 'やや保守的'
        WHEN 2 THEN 'やや積極的' ELSE '積極的'
    END,
    CASE purp_idx
        WHEN 0 THEN '資産保全' WHEN 1 THEN '資産形成' WHEN 2 THEN '老後資金'
        WHEN 3 THEN '年金補完' WHEN 4 THEN '教育資金' ELSE '事業承継'
    END,
    seg_val,
    'RM' || LPAD(CAST(rm_num AS VARCHAR), 3, '0'),
    (r_nisa  > 30),
    (r_ideco > 50),
    (r_trust > 70),
    exp_yr
FROM seg;

-- ============================================================================
-- 3. 家族データ
-- ============================================================================

-- 主要顧客の家族データ
INSERT INTO DIM_FAMILY VALUES
-- 山田太郎様の家族
('F001', 'C001', '配偶者', '山田幸子', 65, '専業主婦', TRUE, 1, NULL, CURRENT_TIMESTAMP()),
('F002', 'C001', '長男', '山田一郎', 40, '会社員', TRUE, 2, '後継者候補', CURRENT_TIMESTAMP()),
('F003', 'C001', '次男', '山田二郎', 38, '医師', TRUE, 3, NULL, CURRENT_TIMESTAMP()),
('F004', 'C001', '長男の配偶者', '山田美咲', 38, '会社員', FALSE, NULL, NULL, CURRENT_TIMESTAMP()),
('F005', 'C001', '孫（長男の子）', '山田健太', 15, '高校生', FALSE, NULL, NULL, CURRENT_TIMESTAMP()),
('F006', 'C001', '孫（長男の子）', '山田美優', 12, '中学生', FALSE, NULL, NULL, CURRENT_TIMESTAMP()),
('F007', 'C001', '孫（次男の子）', '山田翔', 8, '小学生', FALSE, NULL, '海外大学院留学予定', CURRENT_TIMESTAMP()),

-- 鈴木一郎様の家族（事業承継）
('F008', 'C002', '配偶者', '鈴木和子', 70, '専業主婦', TRUE, 1, NULL, CURRENT_TIMESTAMP()),
('F009', 'C002', '長男', '鈴木太郎', 45, '会社役員', TRUE, 2, '後継者・専務取締役', CURRENT_TIMESTAMP()),
('F010', 'C002', '長女', '鈴木美香', 42, '専業主婦', TRUE, 3, '嫁いでいる', CURRENT_TIMESTAMP()),

-- 佐藤花子様の家族
('F011', 'C003', '長男', '佐藤健一', 38, '会社員', TRUE, 1, NULL, CURRENT_TIMESTAMP()),
('F012', 'C003', '長女', '佐藤由美', 35, '公務員', TRUE, 2, NULL, CURRENT_TIMESTAMP()),
('F013', 'C003', '孫', '佐藤陽太', 10, '小学生', FALSE, NULL, NULL, CURRENT_TIMESTAMP()),

-- 高橋健一様の家族
('F014', 'C004', '配偶者', '高橋美智子', 55, '専業主婦', TRUE, 1, NULL, CURRENT_TIMESTAMP()),
('F015', 'C004', '長男', '高橋翔太', 28, '医師', TRUE, 2, '後継者候補・研修医', CURRENT_TIMESTAMP()),
('F016', 'C004', '長女', '高橋理恵', 25, '大学院生', TRUE, 3, NULL, CURRENT_TIMESTAMP()),

-- 伊藤美智子様の家族
('F017', 'C005', '長男', '伊藤正樹', 45, '会社員', TRUE, 1, NULL, CURRENT_TIMESTAMP()),
('F018', 'C005', '次男', '伊藤健二', 42, '自営業', TRUE, 2, '不動産管理を手伝う', CURRENT_TIMESTAMP()),

-- 渡辺正樹様の家族
('F019', 'C006', '配偶者', '渡辺恵子', 58, '専業主婦', TRUE, 1, NULL, CURRENT_TIMESTAMP()),
('F020', 'C006', '長女', '渡辺美咲', 30, '会社員', TRUE, 2, NULL, CURRENT_TIMESTAMP()),
('F021', 'C006', '次女', '渡辺理香', 27, 'フリーランス', TRUE, 3, NULL, CURRENT_TIMESTAMP());

-- 追加の家族データ（残りの顧客用）生成
-- 家族データ追加分（C007-C100）- SQL GENERATOR で一括生成 (150行)
INSERT INTO DIM_FAMILY (FAMILY_ID, CUSTOMER_ID, RELATIONSHIP, FAMILY_AGE, IS_HEIR, HEIR_PRIORITY, CREATED_AT)
WITH g AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY SEQ4()) AS rn,
        UNIFORM(7, 100, RANDOM()) AS cust_num,
        UNIFORM(0,  5, RANDOM()) AS rel_idx,
        UNIFORM(20, 69, RANDOM()) AS fam_age
    FROM TABLE(GENERATOR(ROWCOUNT => 150))
)
SELECT
    'F' || LPAD(CAST(rn + 21 AS VARCHAR), 3, '0'),
    'C' || LPAD(CAST(cust_num AS VARCHAR), 3, '0'),
    CASE rel_idx
        WHEN 0 THEN '配偶者' WHEN 1 THEN '長男' WHEN 2 THEN '長女'
        WHEN 3 THEN '次男'  WHEN 4 THEN '次女' ELSE '孫'
    END,
    fam_age,
    (rel_idx <= 2),
    CASE WHEN rel_idx <= 2 THEN rel_idx + 1 ELSE NULL END,
    CURRENT_TIMESTAMP()
FROM g;

-- ============================================================================
-- 4. ライフイベントデータ
-- ============================================================================

INSERT INTO DIM_LIFE_EVENT VALUES
-- 山田太郎様のライフイベント（デモの中心）
('E001', 'C001', '教育資金', '孫（山田翔）の海外大学院留学', '2026-04-01', 20000000, '高', '相談中', 'F007', '2025-01-08', '2025-01-08', '米国MBA、2年間'),
('E002', 'C001', '相続対策', '相続税対策・遺言書作成', '2026-12-31', 200000000, '中', '検討中', NULL, '2025-01-08', '2025-01-08', '友人の相続トラブルを見て関心'),
('E003', 'C001', '贈与', '教育資金贈与信託の検討', '2026-03-31', 45000000, '高', '計画中', NULL, '2025-01-10', '2025-01-10', '孫3人分、制度終了前に実行希望'),

-- 鈴木一郎様のライフイベント
('E004', 'C002', '事業承継', '自社株承継・事業承継', '2027-03-31', 500000000, '高', '相談中', 'F009', '2024-06-01', '2025-01-10', '長男への株式移転を検討'),
('E005', 'C002', '相続対策', '遺言信託の検討', '2026-06-30', 0, '中', '検討中', NULL, '2024-12-15', '2024-12-15', NULL),

-- 高橋健一様のライフイベント
('E006', 'C004', '事業拡大', 'クリニック分院開設', '2026-06-01', 100000000, '中', '計画中', NULL, '2024-09-01', '2025-01-12', '都内に2院目を検討'),
('E007', 'C004', '教育資金', '長女の大学院留学', '2027-09-01', 15000000, '高', '確定', 'F016', '2024-03-01', '2024-12-20', '英国大学院、1年間'),

-- 渡辺正樹様のライフイベント
('E008', 'C006', '慈善活動', '財団設立・寄付', '2026-12-31', 300000000, '低', '検討中', NULL, '2024-10-01', '2024-10-01', 'テクノロジー教育支援財団'),
('E009', 'C006', '不動産購入', '軽井沢別荘購入', '2027-06-01', 80000000, '中', '相談中', NULL, '2025-01-15', '2025-01-15', NULL),

-- その他顧客のライフイベント
('E010', 'C011', '事業承継', '後継者問題の相談', '2028-03-31', 200000000, '中', '相談中', NULL, '2024-11-01', '2025-01-05', '後継者未定'),
('E011', 'C012', '事業拡大', '分院展開資金', '2026-03-01', 50000000, '中', '計画中', NULL, '2024-08-01', '2025-01-12', NULL),
('E012', 'C016', '教育資金', '子供の私立中学進学', '2026-04-01', 10000000, '高', '確定', NULL, '2024-06-01', '2024-12-25', NULL),
('E013', 'C019', '資産整理', '農地の売却・現金化', '2027-12-31', 150000000, '高', '相談中', NULL, '2024-10-01', '2024-12-18', '後継者不在のため'),
('E014', 'C021', '住宅購入', '住宅ローン借り換え', '2027-06-01', 30000000, '中', '検討中', NULL, '2024-12-01', '2025-01-08', NULL),
('E015', 'C023', '退職', '完全引退・資産整理', '2027-03-31', 0, '低', '検討中', NULL, '2024-09-01', '2024-12-22', NULL),
('E016', 'C026', '相続対策', '子供への生前贈与', '2026-12-31', 30000000, '中', '検討中', NULL, '2024-11-01', '2025-01-03', NULL),
('E017', 'C029', '事業承継', '老舗茶商の事業継続', '2027-06-30', 50000000, '高', '相談中', NULL, '2024-07-01', '2024-12-15', '後継者候補あり（甥）'),
('E018', 'C030', '資産形成', 'FIRE達成目標', '2035-12-31', 100000000, '低', '計画中', NULL, '2024-06-01', '2025-01-15', '45歳でのFIREを目指す');

SELECT 'Part 2: Customer data completed successfully!' AS STATUS;

-- ============================================================================
-- 証券営業インテリジェンス デモ セットアップSQL（汎用版）
-- Part 3: ポートフォリオ & 取引データ
-- ============================================================================

USE DATABASE SNOWFINANCE_DB;
USE SCHEMA DEMO_SCHEMA;
USE WAREHOUSE DEMO_WH;

-- ============================================================================
-- 1. 主要顧客のポートフォリオ（デモ用詳細データ）
-- ============================================================================

-- 山田太郎様のポートフォリオ（8億円）- デモの主人公
INSERT INTO FACT_PORTFOLIO VALUES
-- 国内株式（4億円）
('PF001', 'C001', '国内株式', '7203', 'トヨタ自動車', 50000, 1500, '2010-03-15', 2850, 142500000, 67500000, 90.00, '特定口座', 'JPY', '2026-04-01'),
('PF002', 'C001', '国内株式', '6758', 'ソニーグループ', 20000, 3500, '2012-06-20', 15200, 304000000, 234000000, 334.29, '特定口座', 'JPY', '2026-04-01'),
('PF003', 'C001', '国内株式', '9433', 'KDDI', 15000, 2800, '2015-04-10', 4650, 69750000, 27750000, 66.07, '特定口座', 'JPY', '2026-04-01'),

-- 海外株式（1億円）
('PF004', 'C001', '海外株式', 'AAPL', 'Apple Inc.', 500, 120, '2018-01-15', 185, 13875000, 4875000, 54.17, '特定口座', 'USD', '2026-04-01'),
('PF005', 'C001', '海外株式', 'MSFT', 'Microsoft Corp.', 300, 250, '2019-05-20', 420, 18900000, 7650000, 68.00, '特定口座', 'USD', '2026-04-01'),

-- 国内債券（1.5億円）
('PF006', 'C001', '国内債券', 'JGB10Y', '日本国債10年', 100, 100, '2020-06-01', 98, 98000000, -2000000, -2.00, '特定口座', 'JPY', '2026-04-01'),
('PF007', 'C001', '国内債券', 'CPB001', 'プレミアム社債（国内金融）', 50, 100, '2022-03-15', 101, 50500000, 500000, 1.00, '特定口座', 'JPY', '2026-04-01'),

-- 投資信託（5000万円）
('PF008', 'C001', '投資信託', 'INF001', '日経225インデックスファンド', 500000, 18000, '2021-01-20', 22000, 11000000, 2000000, 22.22, 'NISA', 'JPY', '2026-04-01'),
('PF009', 'C001', '投資信託', 'INF002', 'グローバル株式インデックスファンド', 800000, 25000, '2021-06-15', 32000, 25600000, 5600000, 28.00, 'NISA', 'JPY', '2026-04-01'),
('PF010', 'C001', '投資信託', 'INF003', 'グローバルESG株式ファンド', 400000, 12000, '2023-04-01', 15500, 6200000, 1400000, 29.17, '特定口座', 'JPY', '2026-04-01'),

-- REIT（5000万円）
('PF011', 'C001', 'REIT', '8951', '日本ビルファンド投資法人', 100, 580000, '2019-09-10', 650000, 65000000, 7000000, 12.07, '特定口座', 'JPY', '2026-04-01');

-- 鈴木一郎様のポートフォリオ（15億円）- 事業承継案件
INSERT INTO FACT_PORTFOLIO VALUES
-- 自社株（10億円）
('PF012', 'C002', '国内株式', 'SUZUKI', '鈴木商事株式会社（非上場）', 100000, 5000, '1990-04-01', 10000, 1000000000, 500000000, 100.00, '特定口座', 'JPY', '2026-04-01'),
-- 上場株式
('PF013', 'C002', '国内株式', '8058', '三菱商事', 30000, 2500, '2008-10-15', 3200, 96000000, 21000000, 28.00, '特定口座', 'JPY', '2026-04-01'),
('PF014', 'C002', '国内株式', '8001', '伊藤忠商事', 25000, 1800, '2010-03-20', 7200, 180000000, 135000000, 300.00, '特定口座', 'JPY', '2026-04-01'),
-- 債券
('PF015', 'C002', '外国債券', 'UST10Y', '米国債10年', 100, 95, '2022-01-15', 92, 138000000, -4500000, -3.16, '特定口座', 'USD', '2026-04-01'),
-- 投資信託
('PF016', 'C002', '投資信託', 'INF004', 'グローバル半導体株式ファンド', 1000000, 15000, '2023-06-01', 22000, 22000000, 7000000, 46.67, '特定口座', 'JPY', '2026-04-01'),
('PF017', 'C002', '投資信託', 'INF005', '世界インカム戦略ファンド', 2000000, 10000, '2022-09-15', 11500, 23000000, 3000000, 15.00, '特定口座', 'JPY', '2026-04-01');

-- 高橋健一様のポートフォリオ（12億円）- 医療法人理事長
INSERT INTO FACT_PORTFOLIO VALUES
('PF018', 'C004', '国内株式', '4568', '第一三共', 20000, 3500, '2018-05-10', 4800, 96000000, 26000000, 37.14, '特定口座', 'JPY', '2026-04-01'),
('PF019', 'C004', '国内株式', '4519', '中外製薬', 15000, 4000, '2019-02-20', 6200, 93000000, 33000000, 55.00, '特定口座', 'JPY', '2026-04-01'),
('PF020', 'C004', '海外株式', 'JNJ', 'Johnson & Johnson', 2000, 140, '2020-03-15', 155, 46500000, 4500000, 10.71, '特定口座', 'USD', '2026-04-01'),
('PF021', 'C004', '海外株式', 'PFE', 'Pfizer Inc.', 5000, 35, '2021-01-10', 28, 21000000, -5250000, -20.00, '特定口座', 'USD', '2026-04-01'),
('PF022', 'C004', '国内債券', 'JGB5Y', '日本国債5年', 200, 100, '2023-06-01', 99, 198000000, -2000000, -1.00, '特定口座', 'JPY', '2026-04-01'),
('PF023', 'C004', '投資信託', 'INF006', '先進医療インパクト投資ファンド', 3000000, 12000, '2023-09-01', 14500, 43500000, 7500000, 20.83, 'NISA', 'JPY', '2026-04-01'),
('PF024', 'C004', 'REIT', '3283', '日本プロロジスリート投資法人', 200, 280000, '2021-07-15', 320000, 64000000, 8000000, 14.29, '特定口座', 'JPY', '2026-04-01'),
('PF025', 'C004', '預金', 'DEP', 'マネー・リザーブ・ファンド（MRF）', 1, 1, '2024-01-01', 1, 350000000, 0, 0, '特定口座', 'JPY', '2026-04-01');

-- ============================================================================
-- 2. 追加ポートフォリオデータ（C005-C100）- SQL GENERATOR で一括生成（2026年4月株価）
-- ============================================================================
INSERT INTO FACT_PORTFOLIO (
    PORTFOLIO_ID, CUSTOMER_ID, ASSET_CLASS, SECURITY_CODE, SECURITY_NAME,
    QUANTITY, ACQUISITION_PRICE, ACQUISITION_DATE, CURRENT_PRICE,
    MARKET_VALUE, UNREALIZED_GAIN, UNREALIZED_GAIN_PCT,
    ACCOUNT_TYPE, CURRENCY, AS_OF_DATE
)
WITH g AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY SEQ4()) AS rn,
        UNIFORM(5, 100, RANDOM())   AS cust_num,
        MOD(UNIFORM(0, 999, RANDOM()), 17) AS sec_idx,
        UNIFORM(100, 5000, RANDOM()) AS qty,
        UNIFORM(-25, 45, RANDOM())  AS gain_pct
    FROM TABLE(GENERATOR(ROWCOUNT => 350))
), with_sec AS (
    SELECT
        g.rn,
        'C' || LPAD(CAST(g.cust_num AS VARCHAR), 3, '0') AS customer_id,
        CASE g.sec_idx
            WHEN 0 THEN '国内株式' WHEN 1 THEN '国内株式' WHEN 2 THEN '国内株式'
            WHEN 3 THEN '国内株式' WHEN 4 THEN '国内株式' WHEN 5 THEN '国内株式'
            WHEN 6 THEN '国内株式' WHEN 7 THEN '海外株式' WHEN 8 THEN '海外株式'
            WHEN 9 THEN '海外株式' WHEN 10 THEN '海外株式' WHEN 11 THEN '投資信託'
            WHEN 12 THEN '投資信託' WHEN 13 THEN '投資信託' WHEN 14 THEN '投資信託'
            WHEN 15 THEN '債券'     ELSE '債券'
        END AS asset_class,
        CASE g.sec_idx
            WHEN 0 THEN '7203'   WHEN 1 THEN '6758'   WHEN 2 THEN '9433'
            WHEN 3 THEN '8058'   WHEN 4 THEN '8001'   WHEN 5 THEN '6501'   WHEN 6 THEN '9984'
            WHEN 7 THEN 'AAPL'   WHEN 8 THEN 'MSFT'   WHEN 9 THEN 'NVDA'   WHEN 10 THEN 'AMZN'
            WHEN 11 THEN 'INF001' WHEN 12 THEN 'INF002' WHEN 13 THEN 'INF003' WHEN 14 THEN 'INF005'
            WHEN 15 THEN 'JGB10Y' ELSE 'UST10Y'
        END AS sec_code,
        CASE g.sec_idx
            WHEN 0 THEN 'トヨタ自動車'              WHEN 1 THEN 'ソニーグループ'
            WHEN 2 THEN 'KDDI'                      WHEN 3 THEN '三菱商事'
            WHEN 4 THEN '伊藤忠商事'                WHEN 5 THEN '日立製作所'
            WHEN 6 THEN 'ソフトバンクグループ'      WHEN 7 THEN 'Apple Inc.'
            WHEN 8 THEN 'Microsoft Corp.'           WHEN 9 THEN 'NVIDIA Corp.'
            WHEN 10 THEN 'Amazon.com Inc.'          WHEN 11 THEN '日経225インデックスファンド'
            WHEN 12 THEN 'グローバル株式インデックスファンド'
            WHEN 13 THEN 'グローバルESG株式ファンド'
            WHEN 14 THEN '世界インカム戦略ファンド' WHEN 15 THEN '日本国債10年'
            ELSE '米国債10年'
        END AS sec_name,
        CASE g.sec_idx
            WHEN 0  THEN  3200  WHEN 1  THEN 17500  WHEN 2  THEN  5200
            WHEN 3  THEN  3800  WHEN 4  THEN  8200  WHEN 5  THEN  4500  WHEN 6  THEN 10200
            WHEN 7  THEN   220  WHEN 8  THEN   480  WHEN 9  THEN  1200  WHEN 10 THEN   210
            WHEN 11 THEN 24500  WHEN 12 THEN 36000  WHEN 13 THEN 17200  WHEN 14 THEN 12800
            WHEN 15 THEN    99  ELSE 95
        END AS cur_price,
        CASE WHEN g.sec_idx IN (7,8,9,10,16) THEN 'USD' ELSE 'JPY' END AS currency,
        g.qty,
        g.gain_pct
    FROM g
)
SELECT
    'PF' || LPAD(CAST(rn + 25 AS VARCHAR), 4, '0'),
    customer_id,
    asset_class, sec_code, sec_name,
    CAST(qty AS DECIMAL(18,4)),
    CAST(cur_price / (1.0 + gain_pct / 100.0) AS DECIMAL(18,4)),
    DATEADD('day', -UNIFORM(30, 730, RANDOM()), CURRENT_DATE()),
    CAST(cur_price AS DECIMAL(18,4)),
    CAST(qty * cur_price AS BIGINT),
    CAST(qty * cur_price * gain_pct / (100.0 + gain_pct) AS BIGINT),
    ROUND(gain_pct, 2),
    CASE WHEN UNIFORM(0, 9, RANDOM()) > 7 THEN 'NISA' ELSE '特定口座' END,
    currency,
    CURRENT_DATE()
FROM with_sec;

-- ============================================================================
-- 3. 取引データ（150件）- SQL GENERATOR で一括生成
-- ============================================================================
INSERT INTO FACT_TRANSACTION (
    TRANSACTION_ID, CUSTOMER_ID, TRANSACTION_DATE, TRANSACTION_TYPE,
    ASSET_CLASS, SECURITY_CODE, SECURITY_NAME,
    QUANTITY, PRICE, AMOUNT, FEE, TAX, NET_AMOUNT,
    ACCOUNT_TYPE, ORDER_CHANNEL, RM_ID
)
WITH g AS (
    SELECT
        ROW_NUMBER() OVER (ORDER BY SEQ4()) AS rn,
        UNIFORM(1, 100, RANDOM())  AS cust_num,
        UNIFORM(0,  8,  RANDOM())  AS sec_idx,
        UNIFORM(0,  2,  RANDOM())  AS type_idx,
        UNIFORM(0,  3,  RANDOM())  AS ch_idx,
        UNIFORM(100, 3000, RANDOM()) AS qty,
        UNIFORM(1000, 50000, RANDOM()) AS price,
        UNIFORM(0, 99, RANDOM())   AS nisa_rnd,
        UNIFORM(1, 12, RANDOM())   AS rm_num,
        DATEADD('day', -UNIFORM(0, 450, RANDOM()), CURRENT_DATE()) AS txn_date
    FROM TABLE(GENERATOR(ROWCOUNT => 150))
), calcd AS (
    SELECT
        g.*,
        CASE type_idx WHEN 0 THEN '買付' WHEN 1 THEN '売却' ELSE '配当' END AS txn_type,
        CAST(qty * price AS BIGINT) AS amount_raw
    FROM g
)
SELECT
    'T' || LPAD(CAST(rn + 10 AS VARCHAR), 4, '0'),
    'C' || LPAD(CAST(cust_num AS VARCHAR), 3, '0'),
    txn_date,
    txn_type,
    CASE sec_idx
        WHEN 0 THEN '国内株式' WHEN 1 THEN '国内株式' WHEN 2 THEN '国内株式'
        WHEN 3 THEN '国内株式' WHEN 4 THEN '海外株式' WHEN 5 THEN '海外株式'
        ELSE '投資信託'
    END,
    CASE sec_idx
        WHEN 0 THEN '7203' WHEN 1 THEN '6758' WHEN 2 THEN '9433' WHEN 3 THEN '8058'
        WHEN 4 THEN 'AAPL' WHEN 5 THEN 'MSFT'
        WHEN 6 THEN 'INF001' WHEN 7 THEN 'INF002' ELSE 'INF005'
    END,
    CASE sec_idx
        WHEN 0 THEN 'トヨタ自動車' WHEN 1 THEN 'ソニーグループ'
        WHEN 2 THEN 'KDDI'         WHEN 3 THEN '三菱商事'
        WHEN 4 THEN 'Apple Inc.'   WHEN 5 THEN 'Microsoft Corp.'
        WHEN 6 THEN '日経225インデックスファンド'
        WHEN 7 THEN 'グローバル株式インデックスファンド' ELSE '世界インカム戦略ファンド'
    END,
    qty, price,
    LEAST(amount_raw, 100000000),
    CAST(LEAST(amount_raw, 100000000) * 0.001 AS BIGINT),
    CASE WHEN txn_type = '売却' THEN CAST(LEAST(amount_raw, 100000000) * 0.02 AS BIGINT) ELSE 0 END,
    CASE WHEN txn_type = '売却'
         THEN CAST(LEAST(amount_raw, 100000000) * (1 - 0.001 - 0.02) AS BIGINT)
         ELSE CAST(LEAST(amount_raw, 100000000) * 1.001 AS BIGINT)
    END,
    CASE WHEN nisa_rnd > 70 THEN 'NISA' ELSE '特定口座' END,
    CASE ch_idx WHEN 0 THEN '対面' WHEN 1 THEN 'オンライン' WHEN 2 THEN '電話' ELSE 'システム' END,
    'RM' || LPAD(CAST(rm_num AS VARCHAR), 3, '0')
FROM calcd;

SELECT 'Part 3: Portfolio & Transaction data completed successfully!' AS STATUS;

-- ============================================================================
-- 証券営業インテリジェンス デモ セットアップSQL（汎用版）
-- Part 4: 信託銀行商品 & ニュース & アナリストレポート
-- ============================================================================

USE DATABASE SNOWFINANCE_DB;
USE SCHEMA DEMO_SCHEMA;
USE WAREHOUSE DEMO_WH;

-- ============================================================================
-- 1. プレミアム信託銀行 商品マスタ
-- ============================================================================

INSERT INTO DIM_TRUST_PRODUCT VALUES
-- ローン商品
('TP001', '証券担保ローン', 'Securities-Backed Loan', 'ローン', '有価証券担保', 
 'プレミアム証券に預けている有価証券を担保として、必要な資金をお借入れいただけるローンです。株式売却による税金や機会損失を避けながら、資金ニーズに対応できます。',
 5000000, 1000000000, 1.5, 3.0, 1, 120, 'プライベートバンク,ゴールド', 100000000,
 '株式売却時の約20%の譲渡益課税を回避できます', '担保価値の下落により追加担保が必要になる場合があります',
 TRUE, '2010-04-01', 'プレミアム信託銀行'),

('TP002', '不動産投資ローン', 'Real Estate Investment Loan', 'ローン', '不動産担保',
 '収益不動産（アパート・マンション・商業ビル等）の購入資金を融資するローンです。レバレッジを効かせた不動産投資が可能になります。',
 50000000, 5000000000, 2.0, 4.0, 120, 420, 'プライベートバンク', 300000000,
 '相続税評価額の圧縮効果が期待できます', '空室リスク、金利上昇リスクがあります',
 TRUE, '2015-01-01', 'プレミアム信託銀行'),

-- 相続・贈与関連商品
('TP003', '遺言信託', 'Testamentary Trust', '信託', '遺言関連',
 '遺言書の作成アドバイスから保管、そしてお亡くなりになった後の遺言執行までを一括してお引き受けするサービスです。',
 0, 0, 0, 0, 0, 0, 'プライベートバンク,ゴールド', 100000000,
 '遺産分割協議の紛争を予防できます', NULL,
 TRUE, '2005-04-01', 'プレミアム信託銀行'),

('TP004', '教育資金贈与信託', 'Education Fund Gift Trust', '信託', '贈与関連',
 '30歳未満のお孫様やお子様への教育資金として、1,500万円まで非課税で一括贈与できる信託商品です。',
 0, 15000000, 0, 0, 0, 0, '全セグメント', 0,
 '1,500万円まで贈与税が非課税になります。制度期限：2026年3月31日', '教育目的以外での使用は課税対象となります',
 TRUE, '2013-04-01', 'プレミアム信託銀行'),

('TP005', '結婚・子育て支援信託', 'Marriage & Child-rearing Support Trust', '信託', '贈与関連',
 '20歳以上50歳未満のお子さまやお孫さまへの結婚・出産・子育て資金として、1,000万円まで非課税で贈与できる信託商品です。',
 0, 10000000, 0, 0, 0, 0, '全セグメント', 0,
 '1,000万円まで贈与税が非課税になります', '目的外使用は課税対象となります',
 TRUE, '2015-04-01', 'プレミアム信託銀行'),

-- 事業承継関連
('TP006', '自社株信託', 'Private Company Stock Trust', '信託', '事業承継',
 'オーナー経営者の自社株を信託し、議決権を維持しながら後継者への承継を円滑に進めるための信託商品です。',
 0, 0, 0, 0, 60, 240, 'プライベートバンク', 500000000,
 '株価対策と円滑な事業承継を同時に実現できます', '信託期間中の株式売却に制限があります',
 TRUE, '2018-04-01', 'プレミアム信託銀行'),

('TP007', '特定贈与信託', 'Specified Gift Trust', '信託', '贈与関連',
 '特別障害者の方の生活安定のために、6,000万円まで非課税で贈与できる信託商品です。',
 0, 60000000, 0, 0, 0, 0, '全セグメント', 0,
 '6,000万円まで贈与税が非課税になります', '受益者は特別障害者に限定されます',
 TRUE, '2010-04-01', 'プレミアム信託銀行'),

-- 資産管理関連
('TP008', '金銭信託', 'Money Trust', '信託', '資産管理',
 'プレミアム信託銀行がお客様の資金をお預かりし、安全性を重視した運用を行う信託商品です。',
 10000000, 0, 0.1, 0.5, 12, 60, 'プライベートバンク,ゴールド', 50000000,
 '元本保全を重視した運用が可能です', '市場環境により元本割れの可能性があります',
 TRUE, '2000-04-01', 'プレミアム信託銀行'),

('TP009', '有価証券管理信託', 'Securities Management Trust', '信託', '資産管理',
 'お客様の有価証券を信託財産として管理・保全するサービスです。相続時の名義変更手続きが簡便になります。',
 0, 0, 0, 0, 0, 0, 'プライベートバンク', 100000000,
 '相続時の手続きが簡便になります', NULL,
 TRUE, '2012-04-01', 'プレミアム信託銀行'),

('TP010', '生命保険信託', 'Life Insurance Trust', '信託', '資産管理',
 '生命保険の死亡保険金を信託財産として、指定した方法で受取人に給付するサービスです。',
 0, 0, 0, 0, 0, 0, '全セグメント', 0,
 '保険金の使途を指定できます。障害のあるお子様の生活保障に有効です', NULL,
 TRUE, '2016-04-01', 'プレミアム信託銀行');

-- ============================================================================
-- 2. 商品推奨ロジック
-- ============================================================================

INSERT INTO DIM_PRODUCT_RECOMMENDATION VALUES
-- 証券担保ローンの推奨ロジック
('R001', 'TP001', '教育資金', 50, 80, 100000000, NULL, NULL, 'プライベートバンク',
 '教育資金が必要だが、株式を売却すると多額の税金が発生するケースに最適です。',
 '売却による約20%の譲渡益課税を回避しながら、必要資金を調達できます。株式の上昇益も引き続き享受できます。',
 '【株式売却】税金発生＋株式手放す vs 【担保ローン】金利のみ＋株式保有継続', 1, TRUE),

('R002', 'TP001', '不動産購入', 40, 75, 200000000, NULL, 'やや積極的', 'プライベートバンク',
 '不動産購入の頭金が必要だが、有価証券の売却を避けたいケースに最適です。',
 '金利負担のみで資金調達が可能。不動産取得後は賃料収入でローン返済も可能です。',
 '手持ち資金を使わず、投資ポートフォリオを維持しながら不動産投資が可能', 2, TRUE),

-- 教育資金贈与信託の推奨ロジック
('R003', 'TP004', '教育資金', 55, 80, 100000000, NULL, NULL, NULL,
 '孫の教育資金を非課税で贈与したいケースに最適です。',
 '1,500万円まで贈与税が非課税。ただし制度は2026年3月31日で終了予定のため、早期の検討が必要です。',
 '通常の贈与：年間110万円まで非課税 vs 教育資金贈与信託：1,500万円まで非課税', 1, TRUE),

('R004', 'TP004', '相続対策', 65, 85, 300000000, NULL, NULL, 'プライベートバンク',
 '相続税対策として生前贈与を検討しているケースに最適です。',
 '孫への教育資金贈与で相続財産を減らしながら、孫の将来にも投資できます。',
 '現金で保有 → 相続税課税 vs 教育資金贈与 → 非課税で次世代へ', 2, TRUE),

-- 遺言信託の推奨ロジック
('R005', 'TP003', '相続対策', 65, 90, 200000000, NULL, '保守的', 'プライベートバンク',
 '複雑な資産構成や家族構成で、相続時のトラブルを予防したいケースに最適です。',
 '専門家が遺言書作成をサポートし、保管から執行まで一貫して対応。遺産分割協議の紛争を予防できます。',
 '遺言書なし：相続人全員の合意必要 vs 遺言信託：被相続人の意思を確実に実現', 1, TRUE),

-- 不動産投資ローンの推奨ロジック
('R006', 'TP002', '資産形成', 45, 65, 300000000, NULL, 'やや積極的', 'プライベートバンク',
 '資産分散として不動産投資を検討しているケースに最適です。',
 'レバレッジを効かせた不動産投資が可能。相続税評価額の圧縮効果も期待できます。',
 '現金購入：3億円で1物件 vs ローン活用：自己資金1億円＋ローン2億円で複数物件', 2, TRUE),

('R007', 'TP002', '相続対策', 60, 80, 500000000, NULL, NULL, 'プライベートバンク',
 '相続税評価額を圧縮したいケースに最適です。',
 '不動産は相続税評価額が時価より低くなるため、現金を不動産に換えることで相続税を軽減できます。',
 '現金8億円 → 評価額8億円 vs 不動産8億円 → 評価額約4-5億円', 1, TRUE),

-- 自社株信託の推奨ロジック
('R008', 'TP006', '事業承継', 55, 75, 300000000, NULL, NULL, 'プライベートバンク',
 '自社株の承継を検討しているオーナー経営者に最適です。',
 '議決権を維持しながら、計画的に後継者への株式移転を進められます。株価対策と組み合わせることで税負担も軽減できます。',
 '直接贈与：一度に議決権を手放す vs 自社株信託：段階的に議決権を移転', 1, TRUE);

-- ============================================================================
-- 3. マーケットニュース（50件）
-- ============================================================================

INSERT INTO NEWS_ARTICLES VALUES
-- トヨタ関連（デモで重要）
('N001', '2026-03-15', '2026-03-15 09:30:00', '社内リサーチ', '市況', 
 'トヨタ自動車、来期業績上方修正の可能性 - アナリストレポート',
 'トヨタ自動車(7203)について、アナリストチームは来期の業績上方修正の可能性を指摘した。北米市場でのハイブリッド車販売が好調で、為替も円安基調が継続していることから、営業利益は当初予想を10-15%上回る可能性があるとしている。投資判断は「買い」を維持し、目標株価を3,200円から3,500円に引き上げた。',
 'トヨタ自動車の業績見通しについて分析。ハイブリッド車販売好調と円安効果で来期上方修正の可能性。',
 '7203,トヨタ,TOYOTA', 'ポジティブ', '高', '自動車,製造業,業績予想'),

('N002', '2026-03-14', '2026-03-14 15:00:00', '日本経済新聞', '市況',
 'トヨタ、EV新モデル発表で株価上昇 年初来高値更新',
 'トヨタ自動車は14日、次世代電気自動車(EV)の新モデルを発表した。全固体電池を搭載し、航続距離1,000kmを実現。2026年に量産開始予定。この発表を受け、トヨタ株は前日比3.2%高の2,890円まで上昇し、年初来高値を更新した。',
 'トヨタが次世代EV発表。全固体電池搭載で航続距離1,000km。株価上昇。',
 '7203,トヨタ,EV', 'ポジティブ', '高', '自動車,EV,電池'),

-- 税制改正関連（デモで重要）
('N003', '2026-03-10', '2026-03-10 10:00:00', '財務省', '税制',
 '【速報】教育資金贈与信託、2026年3月末で制度終了へ - 政府税調',
 '政府税制調査会は10日、教育資金の一括贈与に係る非課税措置（教育資金贈与信託）について、2026年3月31日をもって制度を終了する方針を固めた。現行制度では30歳未満の子や孫への教育資金として1,500万円まで非課税で贈与できるが、制度終了後は通常の贈与税が適用される。対象者は早期の対応が求められる。',
 '教育資金贈与信託の非課税措置が2026年3月末で終了へ。早期対応が必要。',
 NULL, 'ニュートラル', '中', '税制改正,贈与税,相続,教育資金'),

('N004', '2026-03-08', '2026-03-08 14:30:00', '国税庁', '税制',
 '2025年度税制改正大綱のポイント - 相続税・贈与税関連',
 '国税庁は2025年度税制改正大綱のポイントを公表した。相続税関連では、相続時精算課税制度の基礎控除が年間110万円に設定され、暦年贈与との選択が可能に。また、事業承継税制の特例措置は2027年まで延長される。富裕層にとっては生前贈与戦略の見直しが必要になる可能性がある。',
 '2025年度税制改正大綱発表。相続時精算課税制度の基礎控除設定、事業承継税制延長など。',
 NULL, 'ニュートラル', '中', '税制改正,相続税,贈与税,事業承継'),

-- 市場動向
('N005', '2026-03-15', '2026-03-15 16:00:00', '東京証券取引所', '市況',
 '日経平均、4万円台を回復 半導体関連株が牽引',
 '15日の東京株式市場で日経平均株価は前日比485円高の40,125円となり、約2ヶ月ぶりに4万円台を回復した。米国のAI関連投資拡大期待から半導体関連株が買われ、相場全体を押し上げた。東京エレクトロン、アドバンテストなどが上昇。',
 '日経平均4万円台回復。半導体関連株が牽引。',
 '8035,6857,日経平均', 'ポジティブ', '中', '日経平均,半導体,AI'),

('N006', '2026-03-13', '2026-03-13 18:00:00', 'Bloomberg', '為替',
 'ドル円、156円台に上昇 日米金利差拡大観測で',
 '外国為替市場でドル円相場は156.50円まで上昇し、約3週間ぶりの円安水準となった。米国のインフレ指標が予想を上回り、FRBの利下げペース鈍化観測が強まったことが背景。日銀は現行の金融政策を維持する見通しで、日米金利差の拡大が円安を後押ししている。',
 'ドル円156円台に上昇。日米金利差拡大で円安進行。',
 'USD/JPY', 'ニュートラル', '中', '為替,ドル円,金利'),

-- ソニー関連
('N007', '2026-03-12', '2026-03-12 11:00:00', '社内リサーチ', '市況',
 'ソニーグループ、ゲーム・音楽事業好調で目標株価引き上げ',
 'ソニーグループ(6758)について、リサーチチームはゲーム事業（PS5販売好調）と音楽事業（ストリーミング収入増）の好調を評価し、目標株価を16,000円から17,500円に引き上げた。投資判断は「買い」を継続。映画事業もスパイダーマン新作のヒットで貢献が期待される。',
 'ソニー目標株価引き上げ。ゲーム・音楽好調。',
 '6758,ソニー,SONY', 'ポジティブ', '中', 'エンターテインメント,ゲーム,音楽'),

-- 金融関連
('N008', '2026-03-11', '2026-03-11 09:00:00', '日本銀行', '金融政策',
 '日銀、金融政策決定会合で現状維持を決定',
 '日本銀行は11日の金融政策決定会合で、短期金利の誘導目標を0-0.1%程度に据え置くことを決定した。植田総裁は記者会見で「物価上昇率は2%目標に向けて緩やかに上昇している」と述べ、今後の経済・物価動向を見極める姿勢を示した。',
 '日銀、金融政策現状維持。利上げは慎重姿勢継続。',
 NULL, 'ニュートラル', '中', '金融政策,日銀,金利'),

-- 不動産関連
('N009', '2026-03-09', '2026-03-09 14:00:00', '不動産経済研究所', '不動産',
 '首都圏マンション価格、過去最高を更新 - 2024年実績',
 '不動産経済研究所の発表によると、2024年の首都圏新築マンション平均価格は8,950万円となり、過去最高を更新した。都心部の用地取得難と建設コスト上昇が背景。投資用マンション市場も堅調で、利回りは4-5%台を維持している。',
 '首都圏マンション価格過去最高。投資市場も堅調。',
 '8951,3283', 'ポジティブ', '中', '不動産,マンション,REIT'),

-- 相続関連
('N010', '2026-03-07', '2026-03-07 10:30:00', '国税庁', '税制',
 '2024年相続税申告件数、過去最多を更新 - 国税庁発表',
 '国税庁は2024年の相続税申告件数が約18万件となり、過去最多を更新したと発表した。高齢化の進展と資産価格の上昇が背景。課税価格の総額は約25兆円で、1件あたりの平均は約1.4億円。相続対策への関心が一段と高まっている。',
 '相続税申告件数過去最多。相続対策への関心高まる。',
 NULL, 'ニュートラル', '中', '相続税,相続対策,高齢化');

-- 追加のニュース（40件）
INSERT INTO NEWS_ARTICLES VALUES
('N011', '2026-03-06', '2026-03-06 09:00:00', 'Reuters', '市況', 'KDDI、5G投資拡大で中期成長見通し引き上げ', 'KDDIは5G関連投資を加速し、2027年度までの中期成長率見通しを引き上げた。法人向けDXサービスも好調で、営業利益率の改善が続く見込み。', 'KDDI中期見通し引き上げ', '9433,KDDI', 'ポジティブ', '中', '通信,5G,DX'),
('N012', '2026-03-05', '2026-03-05 15:00:00', '社内リサーチ', '市況', '三菱商事、資源高で業績好調 - 投資判断「買い」維持', '三菱商事は資源価格の高止まりと非資源分野の成長で業績好調が続く見通し。配当利回りも4%台と魅力的。', '三菱商事業績好調', '8058,三菱商事', 'ポジティブ', '中', '商社,資源,配当'),
('N013', '2026-03-04', '2026-03-04 11:00:00', '日本経済新聞', '市況', '伊藤忠商事、非資源ビジネス拡大で最高益更新へ', '伊藤忠商事は食料・繊維などの非資源分野が好調で、2024年度は純利益の最高益更新が視野に入った。', '伊藤忠最高益へ', '8001,伊藤忠', 'ポジティブ', '中', '商社,非資源'),
('N014', '2026-03-03', '2026-03-03 10:00:00', 'Bloomberg', '為替', '2025年為替見通し：ドル円は150-160円のレンジか', '主要金融機関の2025年為替見通しでは、ドル円は150-160円のレンジで推移するとの予想が多い。日米金利差と日本の経常収支動向が焦点。', '2025年為替見通し', 'USD/JPY', 'ニュートラル', '中', '為替,見通し'),
('N015', '2026-03-02', '2026-03-02 09:00:00', '東京証券取引所', '市況', '2025年大発会、日経平均は小幅上昇でスタート', '2025年最初の取引となった大発会で、日経平均株価は小幅上昇。海外投資家の買いが入り、年初から堅調なスタートとなった。', '大発会小幅上昇', NULL, 'ポジティブ', '低', '日経平均,大発会'),
('N016', '2026-03-28', '2026-03-28 16:00:00', '社内リサーチ', '市況', '【年末特集】2025年注目セクター - 半導体・AI関連', 'リサーチチームは2025年の注目セクターとして半導体・AI関連を挙げた。生成AI需要の拡大でNVIDIA、東京エレクトロンなどに注目。', '2025年注目セクター', '8035,NVDA', 'ポジティブ', '中', '半導体,AI,2025年展望'),
('N017', '2026-03-27', '2026-03-27 14:00:00', '財務省', '税制', '相続税の税務調査強化へ - 海外資産の把握を重点化', '財務省は2025年度から相続税の税務調査を強化する方針。特に海外資産の把握を重点化し、富裕層の申告漏れ対策を進める。', '相続税調査強化', NULL, 'ニュートラル', '中', '相続税,税務調査'),
('N018', '2026-03-26', '2026-03-26 10:00:00', '日本経済新聞', '不動産', '都心オフィス空室率、2%台に低下 - 企業の出社回帰で', '都心5区のオフィス空室率が2%台に低下。コロナ後の出社回帰とAI・DX関連企業の拡大で需要が回復している。', '都心オフィス空室率低下', NULL, 'ポジティブ', '中', '不動産,オフィス'),
('N019', '2026-03-25', '2026-03-25 09:00:00', '内閣府', '経済', 'GDP成長率、2025年は2.0%程度の見通し - 内閣府', '内閣府は2025年度の実質GDP成長率を2.0%程度と予測。インバウンド需要と設備投資の回復が牽引役となる見込み。', 'GDP見通し', NULL, 'ポジティブ', '低', 'GDP,経済成長'),
('N020', '2026-03-24', '2026-03-24 15:00:00', '社内リサーチ', '市況', '日立製作所、DX需要で業績好調 - 目標株価引き上げ', '日立製作所はDXソリューション事業が好調で業績を牽引。リサーチチームは目標株価を4,200円に引き上げ、投資判断「買い」を維持。', '日立目標株価引き上げ', '6501,日立', 'ポジティブ', '中', 'DX,IT'),
('N021', '2026-03-23', '2026-03-23 11:00:00', 'Reuters', '市況', 'ソフトバンクG、AI投資加速で注目高まる', 'ソフトバンクグループはAI分野への投資を加速。Armの業績好調と相まって、株価上昇期待が高まっている。', 'ソフトバンクG AI投資', '9984,SBG', 'ポジティブ', '中', 'AI,投資'),
('N022', '2026-03-22', '2026-03-22 10:00:00', '日本経済新聞', '自動車', 'ホンダ、次世代EV開発に1兆円投資を発表', 'ホンダは2030年までに次世代EV開発に1兆円を投資すると発表。全固体電池の量産化とソフトウェア開発を加速する。', 'ホンダEV投資', '7267,ホンダ', 'ポジティブ', '中', 'EV,自動車'),
('N023', '2026-03-21', '2026-03-21 14:00:00', '社内リサーチ', '市況', 'デンソー、EV関連部品好調で業績上振れ', 'デンソーはEV関連部品の需要増で業績が上振れ。特に熱マネジメント製品が好調で、営業利益率の改善が続く。', 'デンソー業績上振れ', '6902,デンソー', 'ポジティブ', '中', 'EV,自動車部品'),
('N024', '2026-03-20', '2026-03-20 09:00:00', 'Bloomberg', '金融', '米FRB、利下げペース鈍化を示唆 - 12月FOMC', '米FRBは12月のFOMCで政策金利を0.25%引き下げたが、来年の利下げペース鈍化を示唆。ドル高・円安圧力が継続する見通し。', 'FRB利下げ鈍化', NULL, 'ニュートラル', '中', '金融政策,FRB,金利'),
('N025', '2026-03-19', '2026-03-19 15:00:00', '国税庁', '税制', '暦年贈与と相続時精算課税の選択、どちらが有利か - 解説', '2024年税制改正で変更された贈与税制について国税庁が解説資料を公表。暦年贈与と相続時精算課税の選択基準を具体例で示した。', '贈与税制解説', NULL, 'ニュートラル', '中', '贈与税,税制'),
('N026', '2026-03-18', '2026-03-18 11:00:00', '社内リサーチ', '市況', '信越化学、半導体シリコンウェハー需要回復で上方修正期待', '信越化学工業は半導体シリコンウェハーの需要回復で業績上方修正が期待される。投資判断「買い」、目標株価6,500円。', '信越化学上方修正期待', '4063,信越化学', 'ポジティブ', '中', '半導体,素材'),
('N027', '2026-03-17', '2026-03-17 10:00:00', '日本経済新聞', '医薬', '第一三共、がん治療薬が米国で好調 - グローバル展開加速', '第一三共の抗がん剤「エンハーツ」が米国市場で売上好調。パートナーのアストラゼネカとの協業でグローバル展開を加速。', '第一三共がん治療薬好調', '4568,第一三共', 'ポジティブ', '中', '医薬品,がん治療'),
('N028', '2026-03-16', '2026-03-16 14:00:00', '社内リサーチ', '市況', '中外製薬、ロシュとの提携強化で成長加速', '中外製薬は親会社ロシュとの提携を強化し、新薬開発パイプラインを拡充。中長期的な成長が期待される。', '中外製薬成長加速', '4519,中外製薬', 'ポジティブ', '中', '医薬品'),
('N029', '2026-03-15', '2026-03-15 09:00:00', 'Reuters', '不動産', 'Jリート指数、年初来高値更新 - 金利安定で買い安心感', 'Jリート指数が年初来高値を更新。日銀の金利据え置きで金利上昇懸念が後退し、高配当利回りのJリートに買いが入った。', 'Jリート高値更新', '8951,3283', 'ポジティブ', '中', 'REIT,不動産'),
('N030', '2026-03-14', '2026-03-14 16:00:00', '東京証券取引所', '市況', '週間売買代金、過去最高を更新 - 海外マネー流入', '東京証券取引所の週間売買代金が過去最高を更新。海外投資家の日本株買いが活発化し、市場の流動性が向上している。', '売買代金最高', NULL, 'ポジティブ', '中', '株式市場,売買代金');

-- 残り20件
INSERT INTO NEWS_ARTICLES VALUES
('N031', '2026-03-13', '2026-03-13 10:00:00', '日本経済新聞', '経済', '賃上げ率、2025年春闘は5%超の見通し - 経団連', '経団連は2025年春闘の賃上げ率が5%を超える見通しと発表。物価上昇に対応し、実質賃金のプラス転換を目指す。', '賃上げ見通し', NULL, 'ポジティブ', '中', '賃上げ,春闘'),
('N032', '2026-03-12', '2026-03-12 14:00:00', '市況要約', '金融', '証券担保ローン、低金利で利用拡大 - 信託銀行', '信託銀行の証券担保ローンの利用が拡大。低金利環境と株高を背景に、富裕層の資金ニーズに対応している。', '証券担保ローン利用拡大', NULL, 'ポジティブ', '中', 'ローン,信託銀行'),
('N033', '2026-03-11', '2026-03-11 11:00:00', 'Bloomberg', '為替', '円安進行、輸出企業に追い風 - 自動車・電機セクター', '円安進行が輸出企業の業績にプラス。特に自動車・電機セクターでは為替差益の拡大が期待される。', '円安輸出企業追い風', '7203,6758', 'ポジティブ', '中', '為替,輸出'),
('N034', '2026-03-10', '2026-03-10 09:00:00', '日本経済新聞', '金融', 'NISA口座、2024年は過去最高の開設数に', '2024年のNISA口座開設数が過去最高を更新。新NISA制度への移行で投資初心者の参入が加速している。', 'NISA開設最高', NULL, 'ポジティブ', '低', 'NISA,投資'),
('N035', '2026-03-09', '2026-03-09 15:00:00', '社内リサーチ', '市況', '【投資戦略】インフレ環境下での資産配分', 'リサーチチームはインフレ環境下での推奨資産配分を公表。株式50%、債券30%、オルタナティブ20%のポートフォリオを提案。', '資産配分戦略', NULL, 'ニュートラル', '中', '投資戦略,資産配分'),
('N036', '2026-03-08', '2026-03-08 10:00:00', '内閣府', '経済', '景気動向指数、3ヶ月連続で改善 - 内閣府発表', '内閣府発表の景気動向指数は3ヶ月連続で改善。設備投資と個人消費の回復が寄与している。', '景気改善', NULL, 'ポジティブ', '低', '景気,経済指標'),
('N037', '2026-03-07', '2026-03-07 14:00:00', '国税庁', '税制', '事業承継税制の特例措置、2027年末まで延長へ', '事業承継税制の特例措置が2027年末まで延長される見通し。中小企業オーナーの世代交代を後押しする狙い。', '事業承継税制延長', NULL, 'ポジティブ', '中', '事業承継,税制'),
('N038', '2026-03-06', '2026-03-06 11:00:00', '日本経済新聞', '不動産', '軽井沢・箱根など別荘地、富裕層需要で価格上昇', 'リゾート地の別荘需要が増加。テレワーク定着と富裕層の多拠点生活志向で、軽井沢・箱根などの価格が上昇している。', '別荘地価格上昇', NULL, 'ポジティブ', '低', '不動産,別荘'),
('N039', '2026-03-05', '2026-03-05 09:00:00', 'Reuters', '商品', '金価格、過去最高値を更新 - 地政学リスクで買い', '金価格が過去最高値を更新。中東情勢の緊迫化と中央銀行の買い増しで、安全資産としての需要が高まっている。', '金価格最高値', NULL, 'ポジティブ', '中', '金,コモディティ'),
('N040', '2026-03-04', '2026-03-04 15:00:00', '社内リサーチ', '市況', 'Apple、新型iPhone好調で株価上昇', 'AppleのiPhone16シリーズが世界的に好調な売上を記録。AI機能の強化が評価され、株価は年初来高値を更新した。', 'Apple株価上昇', 'AAPL,Apple', 'ポジティブ', '中', 'テック,Apple'),
('N041', '2026-03-03', '2026-03-03 10:00:00', 'Bloomberg', '市況', 'Microsoft、AI事業拡大でクラウド収益増', 'Microsoftのクラウド事業Azureが好調。AI機能の強化で企業向け需要が拡大し、収益成長が加速している。', 'Microsoft AI事業拡大', 'MSFT,Microsoft', 'ポジティブ', '中', 'テック,AI,クラウド'),
('N042', '2026-03-02', '2026-03-02 14:00:00', '社内リサーチ', '市況', 'NVIDIA、データセンター需要で売上倍増', 'NVIDIAのデータセンター向けGPU売上が前年比倍増。生成AI需要の爆発的成長で供給が追いつかない状況が続く。', 'NVIDIA売上倍増', 'NVDA,NVIDIA', 'ポジティブ', '高', 'AI,半導体'),
('N043', '2026-03-01', '2026-03-01 11:00:00', '日本経済新聞', '金融', 'プライベートバンク、富裕層向けサービス拡充競争', '大手証券・銀行がプライベートバンク事業を強化。相続対策や資産運用の高度化ニーズに対応したサービス拡充が進む。', 'PB事業拡充', NULL, 'ニュートラル', '低', 'プライベートバンク,富裕層'),
('N044', '2026-02-25', '2026-02-25 09:00:00', '財務省', '税制', '海外財産調書の提出義務、5000万円超に引き下げ検討', '財務省は海外財産調書の提出義務基準を現行の5000万円超から引き下げることを検討。富裕層の海外資産把握を強化する狙い。', '海外財産調書基準変更', NULL, 'ニュートラル', '中', '税制,海外資産'),
('N045', '2026-02-26', '2026-02-26 15:00:00', '社内リサーチ', '市況', '年末ラリー期待高まる - 日経平均4万2000円視野', 'リサーチチームは年末の株高を予想。海外投資家の買いと国内企業の好業績を背景に、日経平均4万2000円も視野に入ると分析。', '年末ラリー期待', NULL, 'ポジティブ', '中', '株式市場,年末'),
('N046', '2026-02-28', '2026-02-28 10:00:00', '日本経済新聞', '経済', 'インバウンド消費、2024年は過去最高の8兆円見込み', '訪日外国人の消費額が2024年は過去最高の8兆円に達する見込み。円安とアジア富裕層の来日増加が寄与。', 'インバウンド消費最高', NULL, 'ポジティブ', '中', 'インバウンド,消費'),
('N047', '2026-02-27', '2026-02-27 14:00:00', 'Reuters', '為替', '円相場、年末にかけて円安継続か - アナリスト見通し', '主要アナリストの見通しでは、年末にかけて円安基調が継続する見込み。日米金利差と貿易収支の赤字が円安圧力に。', '円安継続見通し', 'USD/JPY', 'ニュートラル', '中', '為替,円安'),
('N048', '2026-02-26', '2026-02-26 11:00:00', '市況要約', '信託', '遺言信託利用、前年比20%増 - 相続対策ニーズ高まる', '信託銀行の遺言信託利用が前年比20%増。高齢化と相続税の課税強化を背景に、相続対策へのニーズが高まっている。', '遺言信託利用増', NULL, 'ポジティブ', '中', '遺言信託,相続'),
('N049', '2026-02-25', '2026-02-25 09:00:00', '日本経済新聞', '経済', 'シニア世代の資産活用、「終活」から「活活」へ', '高齢者の資産活用意識が変化。「死ぬまでに使い切る」から「健康なうちに楽しむ」志向へシフトしている。', 'シニア資産活用', NULL, 'ニュートラル', '低', 'シニア,資産活用'),
('N050', '2026-02-24', '2026-02-24 15:00:00', '社内リサーチ', '市況', '配当利回り4%超銘柄、投資妙味高まる', '高配当株への注目が高まる。配当利回り4%超の銘柄は金利環境を考慮しても魅力的で、長期投資家に人気。', '高配当株注目', '8058,8001', 'ポジティブ', '中', '配当,投資戦略');

SELECT 'Part 4-1: Trust products & News completed!' AS STATUS;

-- ============================================================================
-- 証券営業インテリジェンス デモ セットアップSQL（汎用版）
-- Part 5: アナリストレポート & ローン説明書 & Semantic View
-- ============================================================================

USE DATABASE SNOWFINANCE_DB;
USE SCHEMA DEMO_SCHEMA;
USE WAREHOUSE COMPUTE_WH;

-- ============================================================================
-- 1. アナリストレポート（30件）
-- ============================================================================

INSERT INTO ANALYST_REPORTS VALUES
-- トヨタ（デモで重要）
('AR001', '2026-03-15', '7203', 'トヨタ自動車', '田中アナリスト', '自動車チーム', '買い', '買い', 3500, 3200, 2850, 22.81,
 'トヨタ自動車：ハイブリッド好調と円安効果で目標株価引き上げ',
 'トヨタ自動車の投資判断「買い」を継続し、目標株価を3,200円から3,500円に引き上げる。北米市場でのハイブリッド車販売が予想を上回るペースで推移しており、来期業績の上方修正が期待される。',
 '【投資の着眼点】1)北米ハイブリッド販売好調：RAV4、カムリのHVモデルが前年比30%増。2)円安効果：1円の円安で営業利益450億円の押し上げ効果。3)EV戦略の進展：全固体電池搭載車を2026年に投入予定。【バリュエーション】PER12倍は同業他社比で割安。配当利回り2.8%も魅力的。',
 '1)EV化の遅れ：純粋EVの品揃えが競合に劣る。2)中国市場の苦戦：現地メーカーとの競争激化。3)為替リスク：円高反転時の業績下振れ。',
 '【2025年度予想】売上高45兆円（+5%）、営業利益5.5兆円（+8%）、純利益4.2兆円（+6%）。配当は年間80円を予想。',
 'トヨタ自動車は、ハイブリッド技術の強みを活かした成長が続く見通し。特に北米市場では、EVへの移行が遅れる中でHV需要が拡大しており、トヨタはその恩恵を最も受ける立場にある。来期は営業利益5兆円超えが視野に入り、株価の上昇余地は大きいと判断する。'),

('AR002', '2026-03-20', '7203', 'トヨタ自動車', '田中アナリスト', '自動車チーム', '買い', '中立', 3200, 2800, 2750, 16.36,
 'トヨタ自動車：投資判断を「中立」から「買い」に引き上げ',
 'トヨタ自動車の投資判断を「中立」から「買い」に引き上げる。米国でのHV販売好調と為替の円安進行を評価。',
 '北米でのハイブリッド車販売が好調で、市場シェアを拡大中。EVへの過渡期においてHV戦略が奏功している。',
 '中国市場での苦戦が続く。BYDなど現地メーカーとの競争が激化。',
 '2024年度は営業利益5兆円超えを予想。増配の可能性も。',
 '投資判断引き上げの詳細レポート'),

-- ソニー
('AR003', '2026-03-12', '6758', 'ソニーグループ', '山本アナリスト', 'テクノロジーチーム', '買い', '買い', 17500, 16000, 15200, 15.13,
 'ソニーグループ：ゲーム・音楽好調で目標株価引き上げ',
 'ソニーグループの投資判断「買い」を継続、目標株価を16,000円から17,500円に引き上げ。PS5販売と音楽ストリーミングが好調。',
 '【投資の着眼点】1)ゲーム事業：PS5の累計販売台数が6,000万台突破。ソフト販売も好調。2)音楽事業：ストリーミング収入が前年比15%増。3)映画事業：スパイダーマン新作が大ヒット。',
 'CMOSセンサー事業の競争激化。Samsungとの価格競争が激しい。',
 '2024年度は営業利益1.3兆円を予想。各セグメントで安定成長。',
 'エンターテインメント複合企業として安定した収益基盤を構築。バリュエーション面でも魅力的。'),

-- KDDI
('AR004', '2026-03-06', '9433', 'KDDI', '佐藤アナリスト', '通信チーム', '買い', '買い', 5200, 5000, 4650, 11.83,
 'KDDI：5G投資と法人DXで成長継続',
 'KDDIの投資判断「買い」を継続。5G関連投資の拡大と法人向けDXサービスの成長を評価。安定した配当も魅力。',
 '5G基地局の展開が順調に進み、ARPUの改善が期待される。法人向けDXサービスも高成長を維持。',
 '通信料金の値下げ圧力が継続。楽天モバイルとの競争も注視が必要。',
 '配当利回り3.5%は魅力的。連続増配も期待される。',
 '通信セクターの中で最も安定した銘柄。ディフェンシブ銘柄として推奨。'),

-- 三菱商事
('AR005', '2026-03-05', '8058', '三菱商事', '鈴木アナリスト', '商社チーム', '買い', '買い', 3800, 3500, 3200, 18.75,
 '三菱商事：資源高継続と非資源成長で最高益更新へ',
 '三菱商事の投資判断「買い」を継続。資源価格の高止まりと非資源分野の成長で最高益更新が視野に。配当利回り4%超も魅力。',
 '【投資の着眼点】1)資源価格：LNGと銅価格の高止まりが業績を下支え。2)非資源事業：ローソン、食品事業が安定成長。3)株主還元：総還元性向40%、増配期待。',
 '資源価格の下落リスク。中国経済減速の影響を注視。',
 '純利益1兆円超えを予想。配当は年間200円以上を期待。',
 'バフェット氏の投資で注目度上昇。バリュエーション面で割安。'),

-- 伊藤忠商事
('AR006', '2026-03-04', '8001', '伊藤忠商事', '鈴木アナリスト', '商社チーム', '買い', '買い', 8500, 8000, 7200, 18.06,
 '伊藤忠商事：非資源ビジネスで安定成長',
 '伊藤忠商事の投資判断「買い」を継続。食料・繊維など非資源事業の成長が続き、業績の安定性が高い。',
 '非資源事業の比率が高く、資源価格変動の影響を受けにくい。ファミリーマート事業も堅調。',
 '中国ビジネスのリスク。CITICとの提携事業の動向を注視。',
 '純利益8,500億円を予想。配当は年間170円を見込む。',
 '商社セクターの中で最も安定性の高い銘柄。長期保有に適す。'),

-- 日立
('AR007', '2026-03-24', '6501', '日立製作所', '山本アナリスト', 'テクノロジーチーム', '買い', '買い', 4200, 3800, 3800, 10.53,
 '日立製作所：DX需要で業績好調継続',
 '日立製作所の投資判断「買い」を継続。DXソリューション事業の成長が続き、営業利益率の改善が進む。',
 'Lumadaビジネスが好調で、デジタル売上高比率が50%に迫る。社会インフラ事業も堅調。',
 'パワー半導体事業の競争激化。日立エナジーの収益性改善が課題。',
 '営業利益1兆円達成を予想。ROE15%目標の達成が視野に。',
 '構造改革の成果が出ており、成長軌道に乗った。グローバルIT企業として評価すべき。'),

-- ソフトバンクG
('AR008', '2026-03-23', '9984', 'ソフトバンクグループ', '中村アナリスト', '投資会社チーム', 'やや強気', 'やや強気', 12000, 11000, 9500, 26.32,
 'ソフトバンクG：Arm好調でNAVディスカウント縮小へ',
 'ソフトバンクグループの投資判断「やや強気」を継続。Armの業績好調でNAVディスカウントの縮小が期待される。',
 'Armの売上が前年比40%増と好調。AI需要の拡大でライセンス収入が増加。',
 'ビジョンファンドの投資先評価が不安定。WeWorkの破綻影響も。',
 'Armの価値だけで時価総額を上回る可能性。',
 '投資会社としての評価が難しいが、Armの成長を考慮するとポジティブ。'),

-- 信越化学
('AR009', '2026-03-18', '4063', '信越化学工業', '田中アナリスト', '素材チーム', '買い', '買い', 6500, 6000, 5800, 12.07,
 '信越化学：半導体需要回復で上方修正期待',
 '信越化学の投資判断「買い」を継続。半導体シリコンウェハーの需要回復で業績上方修正が期待される。',
 '300mmウェハーの需要が回復基調。塩ビ事業も堅調を維持。',
 '中国の半導体内製化が長期的なリスク。',
 '営業利益率30%超を維持。財務体質も盤石。',
 '半導体セクターの中で最も安定した銘柄。長期投資に最適。'),

-- 第一三共
('AR010', '2026-03-17', '4568', '第一三共', '井上アナリスト', '医薬品チーム', '買い', '買い', 5500, 5000, 4800, 14.58,
 '第一三共：がん治療薬エンハーツが牽引',
 '第一三共の投資判断「買い」を継続。抗がん剤エンハーツの売上拡大が業績を牽引。新薬パイプラインも充実。',
 'エンハーツの適応拡大が進み、売上は年間1兆円規模に成長見込み。アストラゼネカとの提携も順調。',
 '特許切れリスク。後発品の参入に注意。',
 'エンハーツだけで企業価値の大部分を説明可能。',
 'がん領域のリーダー企業として高く評価。'),

-- 中外製薬
('AR011', '2026-03-16', '4519', '中外製薬', '井上アナリスト', '医薬品チーム', '買い', '買い', 7000, 6500, 6200, 12.90,
 '中外製薬：ロシュとの提携で成長加速',
 '中外製薬の投資判断「買い」を継続。親会社ロシュとの提携強化で新薬開発が加速。アクテムラも堅調。',
 'ロシュの開発品を日本で販売するライセンス契約が収益の柱。自社開発品も増加。',
 'ロシュへの依存度の高さがリスク。',
 '営業利益率40%超の高収益体質。',
 '製薬セクターで最も高い収益性を誇る。'),

-- ホンダ
('AR012', '2026-03-22', '7267', 'ホンダ', '田中アナリスト', '自動車チーム', 'やや強気', '中立', 1900, 1600, 1650, 15.15,
 'ホンダ：EV投資加速で投資判断引き上げ',
 'ホンダの投資判断を「中立」から「やや強気」に引き上げ。EV戦略の明確化と北米事業の好調を評価。',
 '北米でのCR-V、Accordが好調。EV専用工場の建設も順調に進む。',
 '二輪事業の中国市場苦戦。インドネシア市場も競争激化。',
 '四輪事業の収益改善が進む。配当も増加傾向。',
 'EV化への対応が進み、投資妙味が高まった。'),

-- デンソー
('AR013', '2026-03-21', '6902', 'デンソー', '田中アナリスト', '自動車部品チーム', '買い', '買い', 2800, 2600, 2400, 16.67,
 'デンソー：EV関連部品で成長加速',
 'デンソーの投資判断「買い」を継続。EV関連部品、特に熱マネジメント製品の需要拡大が成長を牽引。',
 '熱マネジメント、電動パワートレインが好調。トヨタ向け売上も安定。',
 '半導体不足の影響が残る。原材料価格の上昇も懸念。',
 '営業利益率7%台への改善を予想。',
 'トヨタグループのEV化恩恵を最も受ける銘柄。'),

-- Apple
('AR014', '2026-03-04', 'AAPL', 'Apple', 'Smithアナリスト', 'グローバルテックチーム', '買い', '買い', 210, 195, 185, 13.51,
 'Apple：iPhone16好調とAI機能強化で成長継続',
 'Appleの投資判断「買い」を継続。iPhone16の販売好調とAI機能Apple Intelligenceへの期待で株価上昇が見込まれる。',
 'iPhone16シリーズは初期販売が好調。サービス事業も20%成長が続く。',
 '中国市場でのHuaweiとの競争激化。規制リスクも注視。',
 'サービス売上は年間1,000億ドルを突破へ。',
 'テック株の中で最も安定した収益基盤を持つ。長期保有推奨。'),

-- Microsoft
('AR015', '2026-03-03', 'MSFT', 'Microsoft', 'Smithアナリスト', 'グローバルテックチーム', '買い', '買い', 480, 450, 420, 14.29,
 'Microsoft：Copilot牽引でクラウド事業拡大',
 'Microsoftの投資判断「買い」を継続。AI機能Copilotの導入拡大でAzure収益が加速。',
 'Azure売上は前年比30%増。Copilotの企業導入が進む。Office365も堅調。',
 'AI投資コストの増加。OpenAIとの提携リスク。',
 'クラウド事業は年間1,500億ドル規模に成長へ。',
 'AI時代の最大の受益者として評価。成長と安定性を兼ね備えた銘柄。'),

-- NVIDIA
('AR016', '2026-03-02', 'NVDA', 'NVIDIA', 'Johnsonアナリスト', 'グローバル半導体チーム', '強気', '強気', 1000, 900, 880, 13.64,
 'NVIDIA：AI需要爆発で供給追いつかず',
 'NVIDIAの投資判断「強気」を継続。データセンター向けGPUの需要が爆発的に拡大し、供給が追いつかない状況。',
 'H100、H200の需要が供給を大幅に上回る。データセンター売上は前年比3倍。',
 '競合（AMD、Intel）の追い上げ。中国への輸出規制リスク。',
 '売上高1,000億ドル突破も視野に。',
 'AI半導体市場で圧倒的なシェア。成長株の代表格。'),

-- 追加レポート
('AR017', '2026-02-25', '8951', '日本ビルファンド投資法人', '木村アナリスト', 'REITチーム', '買い', '買い', 720000, 680000, 650000, 10.77, 'Jリート：金利安定で買い安心感', 'オフィス空室率の改善と金利安定で投資妙味が高まる。', 'オフィス需要回復、配当利回り4%超。', '金利上昇リスク。', '分配金は安定推移を予想。', '高配当を求める投資家に最適。'),
('AR018', '2026-02-28', '3283', '日本プロロジスリート投資法人', '木村アナリスト', 'REITチーム', '買い', '買い', 360000, 340000, 320000, 12.50, '物流REIT：EC需要拡大で成長継続', 'EC市場拡大で物流施設需要が堅調。高品質物件に強み。', '稼働率99%超を維持。', '金利上昇時の利回り競争力低下。', '増配傾向が続く見込み。', '物流REITの中で最も安定した銘柄。'),
('AR019', '2026-02-25', '7203', 'トヨタ自動車', '田中アナリスト', '自動車チーム', '買い', '買い', 3200, 3000, 2700, 18.52, 'トヨタ：第2四半期決算レビュー', '2Q決算は市場予想を上回る好決算。通期上方修正の可能性。', '北米、欧州で販売好調。', '中国市場の回復遅れ。', '配当増額の可能性も。', '自動車セクターのトップピック。'),
('AR020', '2026-02-20', '6758', 'ソニーグループ', '山本アナリスト', 'テクノロジーチーム', '買い', '買い', 16000, 15000, 14500, 10.34, 'ソニー：年末商戦に期待', 'PS5とヘッドホンの年末商戦に期待。映画事業も好調。', '各セグメントで安定成長。', 'CMOSセンサーの価格競争。', '営業利益1.2兆円を予想。', 'エンタメ複合企業として安定。'),
('AR021', '2026-02-15', '8058', '三菱商事', '鈴木アナリスト', '商社チーム', '買い', '買い', 3500, 3300, 3100, 12.90, '三菱商事：中間決算レビュー', '中間決算は最高益を更新。通期も過去最高益が視野に。', '資源、非資源ともに好調。', '資源価格の下落リスク。', '増配発表の可能性。', '商社株の中で最も注目。'),
('AR022', '2026-02-10', '4568', '第一三共', '井上アナリスト', '医薬品チーム', '買い', '買い', 5000, 4500, 4600, 8.70, '第一三共：エンハーツ適応拡大', 'エンハーツの適応拡大が承認。さらなる成長が期待される。', 'がん領域でのプレゼンス向上。', '競合品の登場リスク。', '売上1兆円企業へ成長。', 'がん治療領域の成長株。'),
('AR023', '2026-02-05', '9433', 'KDDI', '佐藤アナリスト', '通信チーム', '買い', '買い', 5000, 4800, 4500, 11.11, 'KDDI：中間決算レビュー', '中間決算は堅調。法人DX事業の成長が続く。', '5G、DXで着実に成長。', '料金値下げ圧力。', '配当は年間145円を予想。', 'ディフェンシブ銘柄として安定。'),
('AR024', '2026-01-30', '4063', '信越化学工業', '田中アナリスト', '素材チーム', '買い', '買い', 6000, 5500, 5500, 9.09, '信越化学：半導体需要回復の恩恵', '半導体市況回復でウェハー需要が増加。塩ビも堅調。', '高い利益率を維持。', '中国リスク。', '営業利益率30%台を維持。', '素材セクターのトップピック。'),
('AR025', '2026-01-25', '6501', '日立製作所', '山本アナリスト', 'テクノロジーチーム', '買い', '中立', 3800, 3200, 3500, 8.57, '日立：投資判断引き上げ', 'DX事業の成長を評価し、投資判断を引き上げ。', 'Lumadaビジネス好調。', 'パワー半導体の競争。', 'ROE改善が進む。', '構造改革の成果が出ている。'),
('AR026', '2026-01-20', '8001', '伊藤忠商事', '鈴木アナリスト', '商社チーム', '買い', '買い', 8000, 7500, 7000, 14.29, '伊藤忠：非資源ビジネスで安定成長', '非資源事業比率の高さが強み。ファミマも堅調。', '安定した収益基盤。', '中国CITICとの提携リスク。', '配当は年間160円を予想。', '商社の中で最も安定。'),
('AR027', '2026-01-15', 'AAPL', 'Apple', 'Smithアナリスト', 'グローバルテックチーム', '買い', '買い', 195, 180, 175, 11.43, 'Apple：iPhone16発表レビュー', 'iPhone16発表。AI機能Apple Intelligenceに注目。', '初期販売は好調。', '中国市場の競争。', 'サービス収入が成長牽引。', 'テック株の中で最も安定。'),
('AR028', '2026-01-10', 'MSFT', 'Microsoft', 'Smithアナリスト', 'グローバルテックチーム', '買い', '買い', 450, 420, 410, 9.76, 'Microsoft：Azure成長加速', 'Azure売上成長が加速。Copilot導入も進む。', 'クラウド市場でのシェア拡大。', 'AI投資コスト増。', '営業利益率40%超を維持。', 'AI時代の最大受益者。'),
('AR029', '2026-01-05', 'NVDA', 'NVIDIA', 'Johnsonアナリスト', 'グローバル半導体チーム', '強気', '強気', 900, 800, 750, 20.00, 'NVIDIA：Blackwellアーキテクチャ発表', '次世代GPUアーキテクチャBlackwellを発表。性能大幅向上。', 'AI市場で圧倒的シェア。', '競合の追い上げ。', '売上1,000億ドル視野。', 'AI半導体の絶対王者。'),
('AR030', '2026-01-01', '7267', 'ホンダ', '田中アナリスト', '自動車チーム', '中立', '中立', 1600, 1600, 1500, 6.67, 'ホンダ：中間決算プレビュー', '中間決算は堅調な見通し。北米事業が牽引。', '四輪事業の収益改善。', '二輪の中国市場苦戦。', '配当は年間68円を予想。', 'EV戦略の進展を注視。');

-- ============================================================================
-- 2. ローン商品説明書（チャンク分割済み）
-- ============================================================================

INSERT INTO LOAN_PRODUCT_DOCS VALUES
-- 証券担保ローン
('LD001', 'TP001', '商品説明書', '概要', '証券担保ローンとは',
 '証券担保ローンは、プレミアム証券にお預けいただいている有価証券を担保として、必要な資金をお借入れいただけるローンです。株式を売却することなく、資金ニーズに対応できるため、「売却による税金を避けたい」「株価上昇の機会を逃したくない」というお客様に最適です。プレミアム信託銀行が提供する本サービスは、プレミアム証券のお客様専用のローン商品です。', 1, 1, CURRENT_TIMESTAMP()),

('LD002', 'TP001', '商品説明書', '特徴', '主な特徴とメリット',
 '【主な特徴】1. 株式を売却せずに資金調達：保有株式を担保にするため、売却による機会損失を回避できます。2. 税金の繰り延べ：売却しないため、譲渡益課税（約20%）が発生しません。3. 柔軟な資金使途：教育資金、不動産購入、事業資金など、使途は自由です。4. 迅速な融資実行：審査完了後、最短即日での融資が可能です。5. 金利は低水準：年1.5%〜3.0%の競争力のある金利水準です。', 2, 2, CURRENT_TIMESTAMP()),

('LD003', 'TP001', '商品説明書', '融資条件', '融資条件の詳細',
 '【融資条件】■融資金額：500万円以上10億円以内（担保評価額の50〜70%が上限）■融資期間：1年以上10年以内■金利：年1.5%〜3.0%（変動金利、お客様の取引状況により優遇あり）■担保：当社預かりの上場株式、投資信託、債券等■返済方法：元利均等返済、元金均等返済、期日一括返済から選択可能■手数料：融資事務手数料 融資額の0.5%（税込）', 3, 3, CURRENT_TIMESTAMP()),

('LD004', 'TP001', '商品説明書', '対象顧客', '対象となるお客様',
 '【対象となるお客様】・プレミアム証券に口座をお持ちの個人のお客様・預かり資産1億円以上のお客様（プライベートバンク、ゴールドセグメント）・担保となる有価証券を保有しているお客様・安定した収入または資産があり、返済能力が認められるお客様', 4, 4, CURRENT_TIMESTAMP()),

('LD005', 'TP001', '商品説明書', 'リスク', 'ご注意事項・リスク',
 '【ご注意事項・リスク】■担保価値の下落リスク：担保となる有価証券の価格が下落した場合、追加担保の差入れまたは一部返済が必要になる場合があります。■金利変動リスク：変動金利のため、金利上昇時は返済額が増加します。■強制売却リスク：担保維持率が一定水準を下回り、追加担保の差入れがない場合、担保有価証券が強制売却される場合があります。※ご利用にあたっては、契約締結前交付書面をよくお読みください。', 5, 5, CURRENT_TIMESTAMP()),

('LD006', 'TP001', '商品説明書', '活用事例', '活用事例のご紹介',
 '【活用事例】■事例1：教育資金（山田様・68歳）お孫様の海外留学費用2,000万円が必要に。トヨタ株を売却すると約500万円の税金が発生するため、証券担保ローンで資金調達。株式は保有継続し、株価上昇の機会も逃しませんでした。■事例2：不動産購入（佐藤様・55歳）別荘購入の頭金5,000万円を調達。保有株式を売却せず、投資ポートフォリオを維持したまま不動産投資を実現しました。■事例3：事業資金（田中様・60歳）会社の運転資金として3,000万円を迅速に調達。銀行融資より審査が早く、即日で資金を手配できました。', 6, 6, CURRENT_TIMESTAMP()),

-- 教育資金贈与信託
('LD007', 'TP004', '商品説明書', '概要', '教育資金贈与信託とは',
 '教育資金贈与信託は、30歳未満のお孫様やお子様への教育資金として、1,500万円まで非課税で一括贈与できる信託商品です。通常の贈与では年間110万円までが非課税ですが、本制度を利用することで、まとまった金額を一度に贈与できます。相続財産を減らしながら、次世代の教育を支援できる制度として、多くのお客様にご利用いただいています。', 1, 1, CURRENT_TIMESTAMP()),

('LD008', 'TP004', '商品説明書', '制度概要', '制度の概要と非課税限度額',
 '【制度概要】■非課税限度額：1,500万円（学校等以外への支払いは500万円まで）■対象となる教育資金：・入学金、授業料、入園料、保育料、施設設備費・教科書代、学用品代・修学旅行費、給食費・学習塾、習い事、スポーツ教室の費用（500万円まで）・留学費用（渡航費、滞在費、授業料）■贈与者：直系尊属（祖父母、父母等）■受贈者：30歳未満の直系卑属', 2, 2, CURRENT_TIMESTAMP()),

('LD009', 'TP004', '商品説明書', '制度期限', '【重要】制度期限について',
 '【重要なお知らせ】本制度は、2026年3月31日をもって終了する予定です。終了後は、1,500万円の非課税枠が使えなくなります。制度終了前に贈与をご検討の方は、お早めにご相談ください。■申込期限：2026年3月31日まで■教育資金の払出し：受贈者が30歳になるまで（または学校卒業まで）■残額の取扱い：30歳到達時点で残額がある場合、贈与税が課税されます。', 3, 3, CURRENT_TIMESTAMP()),

-- 遺言信託
('LD010', 'TP003', '商品説明書', '概要', '遺言信託とは',
 '遺言信託は、遺言書の作成アドバイスから保管、そしてお亡くなりになった後の遺言執行までを一括してお引き受けするサービスです。専門家のサポートにより、法的に有効な遺言書を作成し、お客様のご意思を確実に実現します。「家族が揉めないように」「特定の人に財産を渡したい」「社会貢献したい」など、様々なご要望に対応いたします。', 1, 1, CURRENT_TIMESTAMP()),

('LD011', 'TP003', '商品説明書', 'サービス内容', 'サービス内容の詳細',
 '【サービス内容】■遺言書作成コンサルティング：・財産調査、相続人調査・遺言内容のご相談、アドバイス・公正証書遺言の作成サポート■遺言書の保管：・プレミアム信託銀行で厳重に保管・紛失、改ざんのリスクなし■遺言執行：・遺言内容に基づく財産の名義変更・預貯金の解約、不動産の相続登記手続き・遺言内容の確実な実現■定期報告：・年1回、財産状況の変化等を確認・必要に応じて遺言内容の見直しをご提案', 2, 2, CURRENT_TIMESTAMP()),

('LD012', 'TP003', '商品説明書', '費用', '費用について',
 '【費用】■基本報酬：・遺言書作成報酬：33万円（税込）〜・保管料：年間11,000円（税込）■遺言執行報酬（お亡くなり後）：・相続財産の0.5%〜2.0%（最低110万円）※財産の内容、複雑さにより異なります。※詳細は担当者までお問い合わせください。', 3, 3, CURRENT_TIMESTAMP()),

-- 不動産投資ローン
('LD013', 'TP002', '商品説明書', '概要', '不動産投資ローンとは',
 '不動産投資ローンは、収益不動産（アパート・マンション・商業ビル等）の購入資金を融資するローンです。自己資金を抑えながらレバレッジを効かせた不動産投資が可能になります。プレミアム信託銀行の不動産投資ローンは、プレミアム証券のお客様に特化した審査基準と金利優遇をご用意しています。', 1, 1, CURRENT_TIMESTAMP()),

('LD014', 'TP002', '商品説明書', '融資条件', '融資条件の詳細',
 '【融資条件】■融資金額：5,000万円以上50億円以内■融資期間：10年以上35年以内■金利：年2.0%〜4.0%（変動金利）■担保：購入不動産に第一順位の抵当権を設定■対象不動産：一棟収益物件（アパート、マンション、商業ビル等）■融資比率：物件評価額の70〜80%（お客様の属性により変動）', 2, 2, CURRENT_TIMESTAMP()),

('LD015', 'TP002', '商品説明書', 'メリット', 'メリットと活用方法',
 '【メリット】1. レバレッジ効果：自己資金の3〜5倍の物件に投資可能2. 相続税評価額の圧縮：現金→不動産への資産組み換えで評価額ダウン3. インカムゲイン：賃料収入でローン返済と資産形成を両立4. インフレヘッジ：実物資産による資産保全【活用事例】現金8億円を保有→相続税評価額約8億円不動産8億円に組み換え→相続税評価額約4〜5億円（約3〜4億円の評価額圧縮効果）', 3, 3, CURRENT_TIMESTAMP());

-- ============================================================================
-- 3. Cortex Search Service 作成
-- ============================================================================

-- ニュース検索サービス
CREATE OR REPLACE CORTEX SEARCH SERVICE NEWS_SEARCH_SERVICE
ON CONTENT
ATTRIBUTES CATEGORY, TITLE, RELATED_SECURITIES, PUBLISH_DATE
WAREHOUSE = COMPUTE_WH
TARGET_LAG = '1 day'
AS (
    SELECT 
        NEWS_ID,
        PUBLISH_DATE,
        CATEGORY,
        TITLE,
        CONTENT,
        SUMMARY,
        RELATED_SECURITIES,
        SENTIMENT,
        IMPORTANCE
    FROM NEWS_ARTICLES
);

-- ローン商品説明書検索サービス
CREATE OR REPLACE CORTEX SEARCH SERVICE LOAN_DOCS_SEARCH_SERVICE
ON CONTENT
ATTRIBUTES PRODUCT_ID, DOC_TYPE, SECTION, TITLE
WAREHOUSE = COMPUTE_WH
TARGET_LAG = '1 day'
AS (
    SELECT 
        DOC_ID,
        PRODUCT_ID,
        DOC_TYPE,
        SECTION,
        TITLE,
        CONTENT
    FROM LOAN_PRODUCT_DOCS
);

-- アナリストレポート検索サービス
CREATE OR REPLACE CORTEX SEARCH SERVICE ANALYST_REPORT_SEARCH_SERVICE
ON CONTENT
ATTRIBUTES SECURITY_CODE, SECURITY_NAME, RATING, PUBLISH_DATE, ANALYST_NAME
WAREHOUSE = COMPUTE_WH
TARGET_LAG = '1 day'
AS (
    SELECT 
        REPORT_ID,
        PUBLISH_DATE,
        SECURITY_CODE,
        SECURITY_NAME,
        ANALYST_NAME,
        RATING,
        TARGET_PRICE,
        REPORT_TITLE,
        EXECUTIVE_SUMMARY,
        INVESTMENT_THESIS AS CONTENT,
        KEY_RISKS
    FROM ANALYST_REPORTS
);

-- ============================================================================
-- 4. Semantic View 作成（Cortex Analyst 1: 顧客資産管理）
-- ============================================================================

CREATE OR REPLACE SEMANTIC VIEW SNOWFINANCE_DB.DEMO_SCHEMA.CUSTOMER_WEALTH_SEMANTIC_VIEW

TABLES (
    CUSTOMERS AS SNOWFINANCE_DB.DEMO_SCHEMA.DIM_CUSTOMER
        PRIMARY KEY (CUSTOMER_ID)
        WITH SYNONYMS = ('顧客', 'お客様', 'クライアント')
        COMMENT = '顧客マスタテーブル',
    FAMILY AS SNOWFINANCE_DB.DEMO_SCHEMA.DIM_FAMILY
        PRIMARY KEY (FAMILY_ID)
        WITH SYNONYMS = ('家族', '親族', '相続人')
        COMMENT = '家族構成テーブル',
    LIFE_EVENTS AS SNOWFINANCE_DB.DEMO_SCHEMA.DIM_LIFE_EVENT
        PRIMARY KEY (EVENT_ID)
        WITH SYNONYMS = ('ライフイベント', 'イベント', '予定')
        COMMENT = 'ライフイベントテーブル',
    PORTFOLIO AS SNOWFINANCE_DB.DEMO_SCHEMA.FACT_PORTFOLIO
        PRIMARY KEY (PORTFOLIO_ID)
        WITH SYNONYMS = ('ポートフォリオ', '保有資産', '持ち株')
        COMMENT = 'ポートフォリオテーブル',
    TRANSACTIONS AS SNOWFINANCE_DB.DEMO_SCHEMA.FACT_TRANSACTION
        PRIMARY KEY (TRANSACTION_ID)
        WITH SYNONYMS = ('取引', '売買', 'トランザクション')
        COMMENT = '取引履歴テーブル',
    INHERITANCE_TAX AS SNOWFINANCE_DB.DEMO_SCHEMA.V_INHERITANCE_TAX_ESTIMATE
        PRIMARY KEY (CUSTOMER_ID)
        WITH SYNONYMS = ('相続税', '相続税試算')
        COMMENT = '相続税試算ビュー'
)

RELATIONSHIPS (
    CUSTOMERS_TO_FAMILY AS FAMILY (CUSTOMER_ID) REFERENCES CUSTOMERS,
    CUSTOMERS_TO_LIFE_EVENTS AS LIFE_EVENTS (CUSTOMER_ID) REFERENCES CUSTOMERS,
    CUSTOMERS_TO_PORTFOLIO AS PORTFOLIO (CUSTOMER_ID) REFERENCES CUSTOMERS,
    CUSTOMERS_TO_TRANSACTIONS AS TRANSACTIONS (CUSTOMER_ID) REFERENCES CUSTOMERS,
    CUSTOMERS_TO_INHERITANCE_TAX AS INHERITANCE_TAX (CUSTOMER_ID) REFERENCES CUSTOMERS
)

FACTS (
    CUSTOMERS.CUSTOMER_RECORD AS 1 COMMENT = '顧客レコード',
    CUSTOMERS.TOTAL_ASSETS AS TOTAL_ASSETS COMMENT = '総資産',
    CUSTOMERS.LIQUID_ASSETS AS LIQUID_ASSETS COMMENT = '流動資産',
    PORTFOLIO.PORTFOLIO_RECORD AS 1 COMMENT = 'ポートフォリオレコード',
    PORTFOLIO.MARKET_VALUE AS MARKET_VALUE COMMENT = '評価額',
    PORTFOLIO.UNREALIZED_GAIN AS UNREALIZED_GAIN COMMENT = '含み益',
    PORTFOLIO.QUANTITY AS QUANTITY COMMENT = '保有数量',
    TRANSACTIONS.TRANSACTION_RECORD AS 1 COMMENT = '取引レコード',
    TRANSACTIONS.AMOUNT AS AMOUNT COMMENT = '取引金額',
    LIFE_EVENTS.LIFE_EVENT_RECORD AS 1 COMMENT = 'ライフイベントレコード',
    LIFE_EVENTS.ESTIMATED_AMOUNT AS ESTIMATED_AMOUNT COMMENT = '必要金額',
    INHERITANCE_TAX.ESTIMATED_TAX AS ESTIMATED_TAX COMMENT = '推定相続税額'
)

DIMENSIONS (
    CUSTOMERS.CUSTOMER_ID AS CUSTOMER_ID WITH SYNONYMS = ('顧客ID') COMMENT = '顧客ID',
    CUSTOMERS.CUSTOMER_NAME AS CUSTOMER_NAME WITH SYNONYMS = ('顧客名', '氏名') COMMENT = '顧客名',
    CUSTOMERS.AGE AS AGE WITH SYNONYMS = ('年齢') COMMENT = '年齢',
    CUSTOMERS.GENDER AS GENDER WITH SYNONYMS = ('性別') COMMENT = '性別',
    CUSTOMERS.OCCUPATION AS OCCUPATION WITH SYNONYMS = ('職業') COMMENT = '職業',
    CUSTOMERS.PREFECTURE AS PREFECTURE WITH SYNONYMS = ('都道府県', '居住地') COMMENT = '都道府県',
    CUSTOMERS.ANNUAL_INCOME_BAND AS ANNUAL_INCOME_BAND WITH SYNONYMS = ('年収', '年収帯') COMMENT = '年収帯',
    CUSTOMERS.RISK_TOLERANCE AS RISK_TOLERANCE WITH SYNONYMS = ('リスク許容度') COMMENT = 'リスク許容度',
    CUSTOMERS.INVESTMENT_PURPOSE AS INVESTMENT_PURPOSE WITH SYNONYMS = ('投資目的') COMMENT = '投資目的',
    CUSTOMERS.SEGMENT AS SEGMENT WITH SYNONYMS = ('セグメント', '顧客区分') COMMENT = 'セグメント',
    FAMILY.RELATIONSHIP AS RELATIONSHIP WITH SYNONYMS = ('続柄', '関係') COMMENT = '続柄',
    FAMILY.IS_HEIR AS IS_HEIR WITH SYNONYMS = ('相続人フラグ') COMMENT = '相続人フラグ',
    LIFE_EVENTS.EVENT_TYPE AS EVENT_TYPE WITH SYNONYMS = ('イベント種別') COMMENT = 'イベント種別',
    LIFE_EVENTS.URGENCY AS URGENCY WITH SYNONYMS = ('緊急度') COMMENT = '緊急度',
    LIFE_EVENTS.STATUS AS STATUS WITH SYNONYMS = ('ステータス') COMMENT = 'ステータス',
    PORTFOLIO.ASSET_CLASS AS ASSET_CLASS WITH SYNONYMS = ('資産クラス') COMMENT = '資産クラス',
    PORTFOLIO.SECURITY_NAME AS SECURITY_NAME WITH SYNONYMS = ('銘柄名') COMMENT = '銘柄名',
    PORTFOLIO.SECURITY_CODE AS SECURITY_CODE WITH SYNONYMS = ('銘柄コード') COMMENT = '銘柄コード',
    PORTFOLIO.ACCOUNT_TYPE AS ACCOUNT_TYPE WITH SYNONYMS = ('口座種別') COMMENT = '口座種別',
    TRANSACTIONS.TRANSACTION_DATE AS TRANSACTION_DATE WITH SYNONYMS = ('取引日') COMMENT = '取引日',
    TRANSACTIONS.TRANSACTION_TYPE AS TRANSACTION_TYPE WITH SYNONYMS = ('取引種別') COMMENT = '取引種別'
)

METRICS (
    CUSTOMERS.TOTAL_CUSTOMERS AS COUNT(CUSTOMERS.CUSTOMER_RECORD) WITH SYNONYMS = ('顧客数', '人数') COMMENT = '顧客数',
    CUSTOMERS.AVG_TOTAL_ASSETS AS AVG(CUSTOMERS.TOTAL_ASSETS) WITH SYNONYMS = ('平均資産') COMMENT = '平均資産',
    CUSTOMERS.SUM_TOTAL_ASSETS AS SUM(CUSTOMERS.TOTAL_ASSETS) WITH SYNONYMS = ('総資産合計', 'AUM') COMMENT = '総資産合計',
    PORTFOLIO.TOTAL_MARKET_VALUE AS SUM(PORTFOLIO.MARKET_VALUE) WITH SYNONYMS = ('評価額合計', '時価総額') COMMENT = '評価額合計',
    PORTFOLIO.TOTAL_UNREALIZED_GAIN AS SUM(PORTFOLIO.UNREALIZED_GAIN) WITH SYNONYMS = ('含み益合計') COMMENT = '含み益合計',
    TRANSACTIONS.TOTAL_TRANSACTIONS AS COUNT(TRANSACTIONS.TRANSACTION_RECORD) WITH SYNONYMS = ('取引件数') COMMENT = '取引件数',
    TRANSACTIONS.TOTAL_TRANSACTION_AMOUNT AS SUM(TRANSACTIONS.AMOUNT) WITH SYNONYMS = ('取引金額合計') COMMENT = '取引金額合計',
    INHERITANCE_TAX.TOTAL_INHERITANCE_TAX AS SUM(INHERITANCE_TAX.ESTIMATED_TAX) WITH SYNONYMS = ('相続税合計') COMMENT = '相続税合計'
)

COMMENT = '顧客資産管理セマンティックビュー。顧客情報、ポートフォリオ、取引履歴、ライフイベント、相続税試算を統合分析。';

-- ============================================================================
-- 5. Semantic View 作成（Cortex Analyst 2: 信託銀行商品）
-- ============================================================================

CREATE OR REPLACE SEMANTIC VIEW SNOWFINANCE_DB.DEMO_SCHEMA.TRUST_PRODUCT_SEMANTIC_VIEW

  TABLES (
    PRODUCTS AS SNOWFINANCE_DB.DEMO_SCHEMA.DIM_TRUST_PRODUCT 
      PRIMARY KEY (PRODUCT_ID) 
      WITH SYNONYMS = ('商品','信託商品','ローン','product','trust product','loan') 
      COMMENT = '信託銀行の商品マスタ',
    RECOMMENDATIONS AS SNOWFINANCE_DB.DEMO_SCHEMA.DIM_PRODUCT_RECOMMENDATION 
      PRIMARY KEY (RECOMMENDATION_ID) 
      WITH SYNONYMS = ('推奨','レコメンド','提案','recommendation','suggest') 
      COMMENT = '商品推奨ロジック'
  )

  RELATIONSHIPS (
    RECOMMENDATIONS (PRODUCT_ID) REFERENCES PRODUCTS
  )

  FACTS (
  PRODUCTS.MIN_LOAN_AMOUNT AS MIN_AMOUNT 
    WITH SYNONYMS = ('最低金額','最小金額','minimum amount') 
    COMMENT = '最低融資・信託金額',
  PRODUCTS.MAX_LOAN_AMOUNT AS MAX_AMOUNT 
    WITH SYNONYMS = ('最高金額','最大金額','maximum amount') 
    COMMENT = '最高融資・信託金額',
  PRODUCTS.MIN_INTEREST_RATE AS INTEREST_RATE_MIN 
    WITH SYNONYMS = ('最低金利','金利下限','minimum interest rate') 
    COMMENT = '最低金利（%）',
  PRODUCTS.MAX_INTEREST_RATE AS INTEREST_RATE_MAX 
    WITH SYNONYMS = ('最高金利','金利上限','maximum interest rate') 
    COMMENT = '最高金利（%）',
  RECOMMENDATIONS.RECOMMENDATION_PRIORITY AS PRIORITY 
    WITH SYNONYMS = ('優先度','推奨度','priority') 
    COMMENT = '推奨優先度'
)

  DIMENSIONS (
    PRODUCTS.PRODUCT_ID AS PRODUCT_ID 
      WITH SYNONYMS = ('商品ID','ID') 
      COMMENT = '商品識別子',
    PRODUCTS.PRODUCT_NAME AS PRODUCT_NAME 
      WITH SYNONYMS = ('商品名','名称','product name','name') 
      COMMENT = '商品名',
    PRODUCTS.PRODUCT_CATEGORY AS PRODUCT_CATEGORY 
      WITH SYNONYMS = ('商品カテゴリ','種別','category') 
      COMMENT = '商品カテゴリ（ローン/信託）',
    PRODUCTS.PRODUCT_DESCRIPTION AS DESCRIPTION 
      WITH SYNONYMS = ('商品説明','概要','description') 
      COMMENT = '商品説明',
    PRODUCTS.ELIGIBLE_SEGMENT AS ELIGIBLE_SEGMENT 
      WITH SYNONYMS = ('対象セグメント','対象顧客','eligible segment') 
      COMMENT = '対象となる顧客セグメント',
    PRODUCTS.TAX_BENEFIT AS TAX_BENEFIT 
      WITH SYNONYMS = ('税制メリット','節税効果','tax benefit') 
      COMMENT = '税制上のメリット',
    PRODUCTS.RISKS AS RISKS 
      WITH SYNONYMS = ('リスク','注意点','risks') 
      COMMENT = '商品のリスク',
    RECOMMENDATIONS.TARGET_LIFE_EVENT AS TARGET_LIFE_EVENT 
      WITH SYNONYMS = ('対象イベント','推奨シーン','target event') 
      COMMENT = '推奨対象のライフイベント',
    RECOMMENDATIONS.RECOMMENDATION_REASON AS RECOMMENDATION_REASON 
      WITH SYNONYMS = ('推奨理由','提案理由','reason') 
      COMMENT = '推奨理由',
    RECOMMENDATIONS.BENEFIT_DESCRIPTION AS BENEFIT_DESCRIPTION 
      WITH SYNONYMS = ('メリット説明','効果','benefit') 
      COMMENT = 'メリットの説明',
    RECOMMENDATIONS.COMPARISON_WITH_ALTERNATIVE AS COMPARISON_WITH_ALTERNATIVE  
      WITH SYNONYMS = ('比較','代替案との比較','comparison') 
      COMMENT = '代替案との比較'
  )

  METRICS (
    PRODUCTS.PRODUCT_COUNT AS COUNT(PRODUCTS.PRODUCT_ID) 
      WITH SYNONYMS = ('商品数','product count') 
      COMMENT = '商品数',
    RECOMMENDATIONS.RECOMMENDATION_COUNT AS COUNT(RECOMMENDATIONS.RECOMMENDATION_ID) 
      WITH SYNONYMS = ('推奨パターン数','recommendation count') 
      COMMENT = '推奨パターン数'
  )

  COMMENT = '信託銀行商品セマンティックビュー。ローン、信託商品の情報と推奨ロジックを統合。';

SELECT 'Part 5: Reports, Loan Docs & Semantic Views completed successfully!' AS STATUS;

-- ============================================================================
-- 証券営業インテリジェンス デモ セットアップSQL（汎用版）
-- Part 6: Cortex Agent 作成
-- ============================================================================

USE DATABASE SNOWFINANCE_DB;
USE SCHEMA DEMO_SCHEMA;
USE WAREHOUSE DEMO_WH;

-- ============================================================================
-- 1. Cortex Agent 作成
-- ============================================================================

CREATE OR REPLACE AGENT WEALTH_MANAGEMENT_ASSISTANT_AGENT
WITH PROFILE = '{
    "display_name": "ウェルスマネジメントアシスタント"
}'
COMMENT = '証券営業担当者向けの総合支援AIアシスタント。顧客情報、ポートフォリオ分析、信託商品提案、市場ニュース、アナリストレポートを統合して最適な提案を支援します。'
FROM SPECIFICATION $$
{
    "models": {
        "orchestration": ""
    },
    "instructions": {
        "response": "あなたは証券営業担当者を支援するアシスタントです。

【基本原則】
・質問に直接回答し、求められていない情報は出さない
・ツールで取得した情報のみを使用（推測禁止）
・推奨は必ず前提条件付きで提示
・不明点は「確認事項」として明示

【出力形式】
デフォルト：社内メモ（RM向け）
顧客向けトーク：ユーザーが明示した場合のみ

【顧客一覧の出力】
総数→セグメント別内訳→投資目的別内訳→上位10件（ID/資産額/セグメント/投資目的）→絞り込み案
※氏名・住所等の個人属性は一覧に出さない

【個別顧客相談の構造】
1. 確認事項：支払期限、取得単価、流動資産内訳、担保余力
2. 現状サマリ：保有銘柄、時価、含み益
3. 市況（必要時）：媒体名断定せず「社内リサーチ要約」等で表記
4. 選択肢比較（表形式）
5. 推奨（前提条件付き）＋リスク
6. 次アクション

【売却提案のルール】
・資金ニーズに対して過剰な売却は提案しない
・売却株数は「必要額＋税金＋手数料」を満たす最小量
・集中リスク是正はユーザー明示時のみ提案

【税金表示のルール】
・取得単価不明時は税額を確定値で出さない
・数値提示時は必ず：前提（税率/含み益）＋レンジ表示＋「要精緻化」を付記

【相続税計算】
・法定相続人数と基礎控除の整合確認
・孫は法定相続人に含めない
・不明時は概算せず「要確認」

【教育資金贈与信託】
・固有商品名は使用禁止、一般名詞で表現
・期限表現は固定：「現行制度の適用期限は2026年3月31日まで。延長しない方向のため、早めの設計が必要です。」

【禁止事項】
・「まごよろこぶ」「三菱UFJ信託」等の他社商品名出力
・取得単価未確認での税額確定値提示
・必要資金に対する過剰売却・過剰借入の推奨",

        "orchestration": "【ツール選択原則】
・質問に必要なツールのみ使用
・PII（個人情報）は最小限、一覧では匿名化
・チャート表示可能なデータは可視化推奨

【整合性チェック（回答前必須）】
1. 必要資金と提案額（売却/借入）が一致
2. 売却時は税引後手取りが必要資金を充足
3. 取得単価不明時は税額を確定値で記載しない
4. 推奨は前提条件付き（断定禁止）

【ツール選択ルール】
・顧客リスト/検索 → CUSTOMER_ANALYST
・個別顧客照会 → CUSTOMER_ANALYST
・株式売却相談（信託言及なし）→ CUSTOMER_ANALYST のみ
・売却＋ニュース要望 → CUSTOMER_ANALYST + NEWS_SEARCH + ANALYST_REPORT_SEARCH
・信託商品を明示 → CUSTOMER_ANALYST + TRUST_PRODUCT_ANALYST
・商品詳細条件 → LOAN_DOCS_SEARCH

【禁止事項】
・単純売却相談でローン等の代替案を自発提案
・一覧での個人属性（氏名/住所）出力
・教育資金贈与信託の「制度終了」等の断定表現
・禁止商品名の出力"
    },
    "tools": [
        {
            "tool_spec": {
                "type": "cortex_analyst_text_to_sql",
                "name": "CUSTOMER_WEALTH_ANALYST",
                "description": "顧客の資産情報を分析するツール。
取得可能：顧客プロフィール、家族構成、ライフイベント、ポートフォリオ、取引履歴、相続税概算
使用例：「C001の山田太郎様の情報」「資産5億円以上の顧客」「教育資金イベントがある顧客」"
            }
        },
        {
            "tool_spec": {
                "type": "cortex_analyst_text_to_sql",
                "name": "TRUST_PRODUCT_ANALYST",
                "description": "信託銀行の商品情報を検索するツール。
対象：証券担保ローン、教育資金贈与信託、遺言信託、不動産投資ローン、自社株信託
使用例：「証券担保ローンの金利」「教育資金に適した商品」「相続対策の推奨商品」"
            }
        },
        {
            "tool_spec": {
                "type": "cortex_search",
                "name": "NEWS_SEARCH",
                "description": "マーケットニュース・税制改正情報を検索するツール。
回答時は「出典＋日付」を明記。媒体名断定は避け「社内リサーチ要約」等で表記。
使用例：「トヨタの最新ニュース」「教育資金贈与の制度期限」"
            }
        },
        {
            "tool_spec": {
                "type": "cortex_search",
                "name": "LOAN_DOCS_SEARCH",
                "description": "ローン・信託商品の説明書を検索するツール。
取得可能：詳細条件、メリット、リスク、活用事例
使用例：「証券担保ローンの条件詳細」「教育資金贈与信託の非課税限度額」"
            }
        },
        {
            "tool_spec": {
                "type": "cortex_search",
                "name": "ANALYST_REPORT_SEARCH",
                "description": "アナリスト投資レポートを検索するツール。
取得可能：投資判断、目標株価、投資着眼点、リスク、業績予想
回答時は「アナリスト名＋発行日＋投資判断」を明記。
使用例：「トヨタのアナリスト評価」「買い判断の銘柄」"
            }
        }
    ],
    "tool_resources": {
        "CUSTOMER_WEALTH_ANALYST": {
            "semantic_view": "SNOWFINANCE_DB.DEMO_SCHEMA.CUSTOMER_WEALTH_SEMANTIC_VIEW"
        },
        "TRUST_PRODUCT_ANALYST": {
            "semantic_view": "SNOWFINANCE_DB.DEMO_SCHEMA.TRUST_PRODUCT_SEMANTIC_VIEW"
        },
        "NEWS_SEARCH": {
            "name": "SNOWFINANCE_DB.DEMO_SCHEMA.NEWS_SEARCH_SERVICE",
            "max_results": 5,
            "title_column": "TITLE",
            "id_column": "NEWS_ID"
        },
        "LOAN_DOCS_SEARCH": {
            "name": "SNOWFINANCE_DB.DEMO_SCHEMA.LOAN_DOCS_SEARCH_SERVICE",
            "max_results": 5,
            "title_column": "TITLE",
            "id_column": "DOC_ID"
        },
        "ANALYST_REPORT_SEARCH": {
            "name": "SNOWFINANCE_DB.DEMO_SCHEMA.ANALYST_REPORT_SEARCH_SERVICE",
            "max_results": 5,
            "title_column": "REPORT_TITLE",
            "id_column": "REPORT_ID"
        }
    }
}
$$;

-- ============================================================================
-- 2. 確認用クエリ
-- ============================================================================

-- 作成されたオブジェクトの確認
SELECT 'テーブル' AS OBJECT_TYPE, TABLE_NAME AS OBJECT_NAME, ROW_COUNT AS COUNT
FROM INFORMATION_SCHEMA.TABLES 
WHERE TABLE_SCHEMA = 'DEMO_SCHEMA' AND TABLE_TYPE = 'BASE TABLE'
UNION ALL
SELECT 'ビュー' AS OBJECT_TYPE, TABLE_NAME, NULL
FROM INFORMATION_SCHEMA.VIEWS
WHERE TABLE_SCHEMA = 'DEMO_SCHEMA'
ORDER BY OBJECT_TYPE, OBJECT_NAME;

-- Cortex Search Servicesの確認
SHOW CORTEX SEARCH SERVICES IN SCHEMA DEMO_SCHEMA;

-- Agentの確認
SHOW AGENTS IN SCHEMA DEMO_SCHEMA;

SELECT 'Part 6: Agent creation completed successfully!' AS STATUS;
SELECT '========================================' AS SEPARATOR;
SELECT 'セットアップ完了！Snowflake Intelligenceでエージェントをテストしてください。' AS MESSAGE;


-- ============================================================================
-- Part 7: 内部ステージ & Streamlit in Snowflake デプロイ
-- ============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE SNOWFINANCE_DB;
USE SCHEMA DEMO_SCHEMA;
USE WAREHOUSE DEMO_WH;

-- ============================================================================
-- 7.1 内部ステージの作成（目論見書・ドキュメント格納用）
-- ============================================================================
-- 目論見書などのPDFファイルをPUTコマンドでアップロードするための内部ステージ
CREATE OR REPLACE STAGE SNOWFINANCE_DB.DEMO_SCHEMA.PROSPECTUS_STAGE
    ENCRYPTION = (TYPE = 'SNOWFLAKE_SSE')
    DIRECTORY = (ENABLE = TRUE)
    COMMENT = '目論見書・運用報告書などのドキュメントを格納するための内部ステージ';

-- ファイルアップロード例（SnowSQL / Snowflake CLI から実行）:
-- PUT file:///path/to/prospectus.pdf @SNOWFINANCE_DB.DEMO_SCHEMA.PROSPECTUS_STAGE AUTO_COMPRESS=FALSE;
-- PUT後にディレクトリテーブルを最新化:
-- ALTER STAGE SNOWFINANCE_DB.DEMO_SCHEMA.PROSPECTUS_STAGE REFRESH;

-- ステージ確認
SHOW STAGES IN SCHEMA SNOWFINANCE_DB.DEMO_SCHEMA;

-- GitHub リポジトリを登録（DB/Schema が確定した後に作成）
CREATE OR REPLACE GIT REPOSITORY SNOWFINANCE_DB.DEMO_SCHEMA.cortex_ai_handson
    API_INTEGRATION = git_api_integration
    ORIGIN = 'https://github.com/kmotokubota/cortex-ai-handson.git';

-- 最新コンテンツを取得
ALTER GIT REPOSITORY SNOWFINANCE_DB.DEMO_SCHEMA.cortex_ai_handson FETCH;

-- GitリポジトリからPDFファイルを内部ステージにコピー
COPY FILES
    INTO @SNOWFINANCE_DB.DEMO_SCHEMA.PROSPECTUS_STAGE/
    FROM @SNOWFINANCE_DB.DEMO_SCHEMA.cortex_ai_handson/branches/main/docs/prospectus/
    PATTERN = '.*\.pdf';

-- ディレクトリメタデータを更新
ALTER STAGE SNOWFINANCE_DB.DEMO_SCHEMA.PROSPECTUS_STAGE REFRESH;

-- ステージ内のファイル確認
LIST @SNOWFINANCE_DB.DEMO_SCHEMA.PROSPECTUS_STAGE;

SELECT '【Part 7.1】内部ステージ作成 & 目論見書PDFのコピーが完了しました' AS STATUS;

-- ============================================================================
-- 7.2 Streamlit in Snowflake アプリのデプロイ
-- ============================================================================
CREATE OR REPLACE STREAMLIT SNOWFINANCE_DB.DEMO_SCHEMA.WEALTH_MANAGEMENT_DASHBOARD
    FROM @cortex_ai_handson/branches/main/streamlit_app
    MAIN_FILE = 'main.py'
    QUERY_WAREHOUSE = DEMO_WH
    COMMENT = '証券営業インテリジェンス - 顧客資産管理・AI分析ダッシュボード';

-- Streamlitアプリへのアクセス権付与（必要に応じてロールを指定）
-- GRANT USAGE ON STREAMLIT SNOWFINANCE_DB.DEMO_SCHEMA.WEALTH_MANAGEMENT_DASHBOARD TO ROLE <your_role>;

SELECT '【Part 7.2】Streamlit in Snowflakeアプリのデプロイが完了しました' AS STATUS;

-- ============================================================================
-- 完了メッセージ
-- ============================================================================
SELECT '
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ Part 7 セットアップが完了しました！
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ ステージ  : SNOWFINANCE_DB.DEMO_SCHEMA.PROSPECTUS_STAGE
✅ Streamlit : SNOWFINANCE_DB.DEMO_SCHEMA.WEALTH_MANAGEMENT_DASHBOARD

【目論見書のアップロード方法】
  PUT file:///path/to/file.pdf @SNOWFINANCE_DB.DEMO_SCHEMA.PROSPECTUS_STAGE AUTO_COMPRESS=FALSE;
  ALTER STAGE SNOWFINANCE_DB.DEMO_SCHEMA.PROSPECTUS_STAGE REFRESH;
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
' AS "✅ Part 7 完了";
