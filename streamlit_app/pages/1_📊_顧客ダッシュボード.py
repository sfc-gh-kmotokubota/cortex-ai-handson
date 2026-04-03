import streamlit as st
import pandas as pd
import plotly.graph_objects as go
import plotly.express as px
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from utils import get_session

st.set_page_config(layout="wide")

COLORS = {
    'primary':   '#29B5E8',
    'secondary': '#11567F',
    'accent':    '#F5B800',
    'positive':  '#10B981',
    'negative':  '#EF4444',
    'neutral':   '#6B7280',
}

session = get_session()


def format_oku(value: float) -> str:
    if pd.isna(value):
        return "-"
    if value >= 1_0000_0000:
        return f"¥{value/1_0000_0000:.1f}億"
    elif value >= 10_000:
        return f"¥{value/10_000:.0f}万"
    return f"¥{value:,.0f}"


@st.cache_data(ttl=300)
def get_customer_summary():
    df = session.sql("""
        SELECT
            COUNT(*)                          AS TOTAL_CUSTOMERS,
            SUM(TOTAL_ASSETS)                 AS TOTAL_AUM,
            AVG(TOTAL_ASSETS)                 AS AVG_AUM,
            COUNT(CASE WHEN RISK_TOLERANCE = '積極的' THEN 1 END)   AS AGGRESSIVE_COUNT,
            COUNT(CASE WHEN RISK_TOLERANCE = '保守的' THEN 1 END)  AS CONSERVATIVE_COUNT,
            COUNT(CASE WHEN RISK_TOLERANCE = 'やや積極的' THEN 1 END)  AS MODERATE_COUNT
        FROM SNOWFINANCE_DB.DEMO_SCHEMA.DIM_CUSTOMER
    """).to_pandas()
    return df.iloc[0].to_dict()


@st.cache_data(ttl=300)
def get_customers():
    return session.sql("""
        SELECT
            c.CUSTOMER_ID,
            c.CUSTOMER_NAME,
            c.AGE,
            c.OCCUPATION,
            c.RISK_TOLERANCE,
            c.TOTAL_ASSETS,
            c.INVESTMENT_EXPERIENCE_YEARS
        FROM SNOWFINANCE_DB.DEMO_SCHEMA.DIM_CUSTOMER c
        ORDER BY c.TOTAL_ASSETS DESC
    """).to_pandas()


@st.cache_data(ttl=300)
def get_risk_distribution():
    return session.sql("""
        SELECT RISK_TOLERANCE, COUNT(*) AS CNT
        FROM SNOWFINANCE_DB.DEMO_SCHEMA.DIM_CUSTOMER
        GROUP BY RISK_TOLERANCE
        ORDER BY CNT DESC
    """).to_pandas()


@st.cache_data(ttl=300)
def get_life_events():
    return session.sql("""
        SELECT
            l.CUSTOMER_ID,
            c.CUSTOMER_NAME,
            l.EVENT_TYPE,
            l.EVENT_DETAIL,
            l.EXPECTED_DATE,
            l.URGENCY,
            l.STATUS
        FROM SNOWFINANCE_DB.DEMO_SCHEMA.DIM_LIFE_EVENT l
        JOIN SNOWFINANCE_DB.DEMO_SCHEMA.DIM_CUSTOMER c ON l.CUSTOMER_ID = c.CUSTOMER_ID
        ORDER BY l.EXPECTED_DATE ASC
        LIMIT 20
    """).to_pandas()


st.title("📊 顧客ダッシュボード")
st.markdown("富裕層顧客の全体像とライフイベント一覧")
st.markdown("---")

summary = get_customer_summary()
customers = get_customers()
risk_dist = get_risk_distribution()
life_events = get_life_events()

col1, col2, col3, col4 = st.columns(4)
with col1:
    st.metric("総顧客数", f"{int(summary.get('TOTAL_CUSTOMERS', 0))}名")
with col2:
    st.metric("総 AUM", format_oku(summary.get('TOTAL_AUM', 0)))
with col3:
    st.metric("平均 AUM", format_oku(summary.get('AVG_AUM', 0)))
with col4:
    st.metric("積極的顧客", f"{int(summary.get('AGGRESSIVE_COUNT', 0))}名")

st.markdown("---")

col_left, col_right = st.columns(2)

with col_left:
    st.subheader("🥧 リスク許容度の分布")
    if not risk_dist.empty:
        fig = go.Figure(data=[go.Pie(
            labels=risk_dist['RISK_TOLERANCE'].tolist(),
            values=risk_dist['CNT'].tolist(),
            hole=0.45,
            marker_colors=[COLORS['primary'], COLORS['accent'], COLORS['positive'], COLORS['secondary']]
        )])
        fig.update_layout(height=320, margin=dict(l=20, r=20, t=20, b=40),
                          legend=dict(orientation="h", yanchor="bottom", y=-0.2))
        st.plotly_chart(fig, use_container_width=True)

with col_right:
    st.subheader("💼 AUM 上位 10 顧客")
    if not customers.empty:
        top10 = customers.head(10).copy()
        top10['AUM_表示'] = top10['TOTAL_ASSETS'].apply(format_oku)
        fig_bar = go.Figure(go.Bar(
            x=top10['TOTAL_ASSETS'].tolist(),
            y=top10['CUSTOMER_NAME'].tolist(),
            orientation='h',
            marker_color=COLORS['primary'],
            text=top10['AUM_表示'].tolist(),
            textposition='outside'
        ))
        fig_bar.update_layout(height=320, margin=dict(l=20, r=20, t=20, b=20),
                               xaxis_title="総資産 (円)", yaxis=dict(autorange='reversed'))
        st.plotly_chart(fig_bar, use_container_width=True)

st.markdown("---")

st.subheader("📋 顧客一覧")

risk_options = ["全て"] + list(customers['RISK_TOLERANCE'].dropna().unique())
selected_risk = st.selectbox("リスク許容度でフィルター", risk_options)

filtered = customers if selected_risk == "全て" else customers[customers['RISK_TOLERANCE'] == selected_risk]

display_customers = filtered.copy()
display_customers['TOTAL_ASSETS'] = display_customers['TOTAL_ASSETS'].apply(format_oku)
display_customers.columns = ['顧客ID', '氏名', '年齢', '職業', 'リスク許容度', '総資産', '投資経験']
st.dataframe(display_customers, use_container_width=True)

st.markdown("---")

st.subheader("📅 最近のライフイベント")

if not life_events.empty:
    for _, row in life_events.iterrows():
        with st.container():
            col_a, col_b = st.columns([3, 1])
            with col_a:
                st.markdown(f"**{row['CUSTOMER_NAME']}** — {row['EVENT_TYPE']}")
                if pd.notna(row.get('EVENT_DETAIL')):
                    st.caption(row['EVENT_DETAIL'])
            with col_b:
                st.caption(str(row.get('EXPECTED_DATE', ''))[:10])
else:
    st.info("ライフイベントデータがありません。")

st.markdown("---")
st.caption("💡 詳細な資産分析は「ポートフォリオ分析」ページで行えます。")
