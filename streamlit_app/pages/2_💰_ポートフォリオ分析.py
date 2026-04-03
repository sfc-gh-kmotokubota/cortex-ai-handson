import streamlit as st
import pandas as pd
import plotly.graph_objects as go
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
def get_customer_list():
    return session.sql("""
        SELECT CUSTOMER_ID, CUSTOMER_NAME
        FROM SNOWFINANCE_DB.DEMO_SCHEMA.DIM_CUSTOMER
        ORDER BY TOTAL_ASSETS DESC
    """).to_pandas()


@st.cache_data(ttl=300)
def get_portfolio(customer_id: str):
    return session.sql(f"""
        SELECT
            p.SECURITY_CODE,
            p.SECURITY_NAME,
            p.ASSET_CLASS,
            p.QUANTITY,
            p.ACQUISITION_PRICE,
            p.CURRENT_PRICE,
            p.MARKET_VALUE,
            p.UNREALIZED_GAIN,
            p.UNREALIZED_GAIN_PCT
        FROM SNOWFINANCE_DB.DEMO_SCHEMA.FACT_PORTFOLIO p
        WHERE p.CUSTOMER_ID = '{customer_id}'
        ORDER BY p.MARKET_VALUE DESC
    """).to_pandas()


@st.cache_data(ttl=300)
def get_asset_class_summary(customer_id: str):
    return session.sql(f"""
        SELECT
            ASSET_CLASS,
            SUM(MARKET_VALUE)  AS TOTAL_MV,
            SUM(UNREALIZED_GAIN) AS TOTAL_PL,
            COUNT(*)           AS HOLDING_COUNT
        FROM SNOWFINANCE_DB.DEMO_SCHEMA.FACT_PORTFOLIO
        WHERE CUSTOMER_ID = '{customer_id}'
        GROUP BY ASSET_CLASS
        ORDER BY TOTAL_MV DESC
    """).to_pandas()


st.title("💰 ポートフォリオ分析")
st.markdown("顧客別の資産配分・銘柄損益・リスク分析")
st.markdown("---")

customers = get_customer_list()
customer_options = {row['CUSTOMER_NAME']: row['CUSTOMER_ID'] for _, row in customers.iterrows()}

selected_name = st.selectbox("顧客を選択", list(customer_options.keys()))
selected_id = customer_options[selected_name]

portfolio = get_portfolio(selected_id)
asset_summary = get_asset_class_summary(selected_id)

if portfolio.empty:
    st.warning(f"{selected_name} のポートフォリオデータが見つかりません。")
    st.stop()

total_mv = portfolio['MARKET_VALUE'].sum()
total_pl = portfolio['UNREALIZED_GAIN'].sum()
total_pl_rate = (total_pl / (total_mv - total_pl) * 100) if (total_mv - total_pl) != 0 else 0
holding_count = len(portfolio)

col1, col2, col3, col4 = st.columns(4)
with col1:
    st.metric("時価評価額合計", format_oku(total_mv))
with col2:
    delta_color = "normal" if total_pl >= 0 else "inverse"
    st.metric("含み損益合計", format_oku(total_pl), delta=f"{total_pl_rate:+.2f}%", delta_color=delta_color)
with col3:
    st.metric("保有銘柄数", f"{holding_count}銘柄")
with col4:
    best_row = portfolio.loc[portfolio['UNREALIZED_GAIN_PCT'].idxmax()]
    st.metric("最高パフォーマー", best_row['SECURITY_NAME'][:12],
              delta=f"{best_row['UNREALIZED_GAIN_PCT']:+.1f}%")

st.markdown("---")

col_left, col_right = st.columns(2)

with col_left:
    st.subheader("🥧 アセットクラス別配分")
    if not asset_summary.empty:
        fig_pie = go.Figure(data=[go.Pie(
            labels=asset_summary['ASSET_CLASS'].tolist(),
            values=asset_summary['TOTAL_MV'].tolist(),
            hole=0.45,
            textinfo='label+percent'
        )])
        fig_pie.update_layout(height=340, margin=dict(l=20, r=20, t=20, b=40),
                               legend=dict(orientation="h", yanchor="bottom", y=-0.25))
        st.plotly_chart(fig_pie, use_container_width=True)

with col_right:
    st.subheader("📊 アセットクラス別損益")
    if not asset_summary.empty:
        colors = [COLORS['positive'] if v >= 0 else COLORS['negative']
                  for v in asset_summary['TOTAL_PL'].tolist()]
        fig_bar = go.Figure(go.Bar(
            x=asset_summary['ASSET_CLASS'].tolist(),
            y=asset_summary['TOTAL_PL'].tolist(),
            marker_color=colors,
            text=[format_oku(v) for v in asset_summary['TOTAL_PL'].tolist()],
            textposition='outside'
        ))
        fig_bar.update_layout(height=340, margin=dict(l=20, r=20, t=20, b=40),
                               xaxis_title="アセットクラス", yaxis_title="含み損益 (円)")
        st.plotly_chart(fig_bar, use_container_width=True)

st.markdown("---")

st.subheader("🏆 銘柄別損益ランキング")

col_gain, col_loss = st.columns(2)

with col_gain:
    st.markdown("#### ✨ 含み益 TOP 5")
    top_gain = portfolio.nlargest(5, 'UNREALIZED_GAIN')[
        ['SECURITY_NAME', 'ASSET_CLASS', 'MARKET_VALUE', 'UNREALIZED_GAIN', 'UNREALIZED_GAIN_PCT']
    ].reset_index(drop=True)

    for rank, (_, row) in enumerate(top_gain.iterrows(), 1):
        with st.container():
            col_r, col_n = st.columns([1, 5])
            with col_r:
                st.markdown(f"### {'🥇' if rank==1 else '🥈' if rank==2 else '🥉' if rank==3 else rank}")
            with col_n:
                st.markdown(f"**{row['SECURITY_NAME']}**")
                st.caption(row['ASSET_CLASS'])
            m1, m2, m3 = st.columns(3)
            m1.metric("時価", format_oku(row['MARKET_VALUE']))
            m2.metric("含み損益", format_oku(row['UNREALIZED_GAIN']))
            m3.metric("損益率", f"{row['UNREALIZED_GAIN_PCT']:+.1f}%")

with col_loss:
    st.markdown("#### ⚠️ 含み損 WORST 5")
    top_loss = portfolio.nsmallest(5, 'UNREALIZED_GAIN')[
        ['SECURITY_NAME', 'ASSET_CLASS', 'MARKET_VALUE', 'UNREALIZED_GAIN', 'UNREALIZED_GAIN_PCT']
    ].reset_index(drop=True)

    for rank, (_, row) in enumerate(top_loss.iterrows(), 1):
        with st.container():
            col_r, col_n = st.columns([1, 5])
            with col_r:
                st.markdown(f"### {rank}")
            with col_n:
                st.markdown(f"**{row['SECURITY_NAME']}**")
                st.caption(row['ASSET_CLASS'])
            m1, m2, m3 = st.columns(3)
            m1.metric("時価", format_oku(row['MARKET_VALUE']))
            m2.metric("含み損益", format_oku(row['UNREALIZED_GAIN']))
            m3.metric("損益率", f"{row['UNREALIZED_GAIN_PCT']:+.1f}%")

st.markdown("---")

st.subheader("📋 保有銘柄一覧")

disp = portfolio.copy()
disp['MARKET_VALUE']      = disp['MARKET_VALUE'].apply(format_oku)
disp['UNREALIZED_GAIN']     = disp['UNREALIZED_GAIN'].apply(format_oku)
disp['UNREALIZED_GAIN_PCT'] = disp['UNREALIZED_GAIN_PCT'].apply(lambda x: f"{x:+.2f}%" if pd.notna(x) else "-")
disp['ACQUISITION_PRICE']    = disp['ACQUISITION_PRICE'].apply(lambda x: f"{x:,.0f}" if pd.notna(x) else "-")
disp['CURRENT_PRICE']     = disp['CURRENT_PRICE'].apply(lambda x: f"{x:,.0f}" if pd.notna(x) else "-")
disp.columns = ['コード', '銘柄名', 'クラス', '数量', '取得単価', '現在値', '時価', '含み損益', '損益率']
st.dataframe(disp, use_container_width=True)

st.markdown("---")
st.caption("💡 AI による投資アドバイスは「AI 分析」ページで確認できます。")
