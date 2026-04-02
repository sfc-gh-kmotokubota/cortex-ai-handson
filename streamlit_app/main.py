import streamlit as st
from utils import get_session

st.set_page_config(
    page_title="富裕層顧客インテリジェンス",
    layout="wide",
    initial_sidebar_state="expanded"
)

session = get_session()

if "selected_model" not in st.session_state:
    st.session_state.selected_model = "claude-sonnet-4-6"

st.title("💼 富裕層顧客インテリジェンス")
st.header("証券営業 AI ダッシュボード")

st.markdown("""
Snowflake Cortex AI を活用した証券営業支援プラットフォームです。
顧客ポートフォリオ分析・AI インサイト・ニュース分析を一元管理できます。
""")

st.markdown("---")

st.subheader("📌 機能一覧")

col1, col2 = st.columns(2)

with col1:
    with st.container(border=True):
        st.markdown("### 📊 顧客ダッシュボード")
        st.markdown("富裕層顧客の全体像を把握。")
        st.markdown("""
        - 顧客 KPI サマリー（AUM・顧客数）
        - 顧客セグメント分布
        - ライフイベント一覧
        """)

    with st.container(border=True):
        st.markdown("### 💰 ポートフォリオ分析")
        st.markdown("顧客別の資産配分と損益を可視化。")
        st.markdown("""
        - アセットクラス別配分（円グラフ）
        - 銘柄別損益ランキング
        - リスク・リターン分析
        """)

with col2:
    with st.container(border=True):
        st.markdown("### 🤖 AI 分析")
        st.markdown("Cortex AI で顧客インサイトを自動生成。")
        st.markdown("""
        - **AI_COMPLETE** によるアドバイス生成・レポート要約
        - **AI_SENTIMENT** によるニュース感情分析
        - アナリストレポート構造データ一覧
        """)

    with st.container(border=True):
        st.markdown("### 📰 ニュース分析")
        st.markdown("関連ニュースの重要度・感情を可視化。")
        st.markdown("""
        - IMPORTANCE スコア別フィルター
        - AI_SENTIMENT 感情ラベル（positive/negative）
        - 銘柄・顧客別ニュース検索
        """)

st.markdown("---")

st.subheader("🚀 活用している Snowflake Cortex AI 関数")

with st.container(border=True):
    col1, col2, col3, col4 = st.columns(4)

    with col1:
        st.markdown("#### 🤖 AI_COMPLETE")
        st.markdown("自由形式プロンプトで顧客向けアドバイスを生成。")

    with col2:
        st.markdown("#### 😊 AI_SENTIMENT")
        st.markdown("ニュース記事の感情を positive/negative で判定。")

    with col3:
        st.markdown("#### 📊 アナリストレポート")
        st.markdown("保有銘柄のレーティング・目標株価を構造表示。")

    with col4:
        st.markdown("#### 🔍 AI_EXTRACT")
        st.markdown("非構造化テキストからキーワードを抽出。")

st.markdown("---")

st.subheader("🎯 クイックスタート")

with st.container(border=True):
    st.markdown("""
**はじめての方へ**

1. 📊 **顧客ダッシュボード** で全体の顧客状況を確認
2. 💰 **ポートフォリオ分析** で個別顧客の資産を深掘り
3. 🤖 **AI 分析** で Cortex AI による自動インサイトを確認
4. 📰 **ニュース分析** で関連ニュースのトレンドを把握

👈 左側のサイドバーから各ページにアクセスしてください。
    """)

st.markdown("---")

with st.expander("📚 データソースについて"):
    st.markdown("""
| データソース | 説明 |
|-------------|------|
| `DIM_CUSTOMER` | 富裕層顧客マスタ（100名） |
| `FACT_PORTFOLIO` | 保有銘柄・損益データ |
| `DIM_LIFE_EVENT` | ライフイベント履歴 |
| `DIM_FAMILY` | 家族構成データ |
| `NEWS_ARTICLES` | 関連ニュース（IMPORTANCE: '高'/'中'/'低'） |
| `ANALYST_REPORTS` | アナリストレポート |
| `CUSTOMER_WEALTH_SEMANTIC_VIEW` | 顧客資産セマンティックビュー |

データベース: `SNOWFINANCE_DB.DEMO_SCHEMA`
    """)

st.markdown("---")
st.caption("**富裕層顧客インテリジェンス** | Powered by Snowflake Cortex AI")
