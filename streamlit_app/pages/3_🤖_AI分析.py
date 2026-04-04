import re
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
    'primary':  '#29B5E8',
    'positive': '#10B981',
    'negative': '#EF4444',
    'neutral':  '#6B7280',
    'accent':   '#F5B800',
    'upgrade':  '#10B981',
    'downgrade':'#EF4444',
    'maintain': '#6B7280',
}

IMP_STARS_MAP = {'高': '⭐⭐⭐', '中': '⭐⭐', '低': '⭐'}

session = get_session()


def format_oku(value: float) -> str:
    if pd.isna(value):
        return "-"
    if value >= 1_0000_0000:
        return f"¥{value/1_0000_0000:.1f}億"
    elif value >= 10_000:
        return f"¥{value/10_000:.0f}万"
    return f"¥{value:,.0f}"


def clean_ai_output(text: str) -> str:
    text = text.strip()
    if text.startswith('"') and text.endswith('"'):
        text = text[1:-1]
    text = text.replace('\\n', '\n')
    text = text.replace('\\t', '\t')
    text = text.replace('\\"', '"')
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text


@st.cache_data(ttl=300)
def get_customer_list():
    return session.sql("""
        SELECT CUSTOMER_ID, CUSTOMER_NAME, TOTAL_ASSETS, RISK_TOLERANCE
        FROM SNOWFINANCE_DB.DEMO_SCHEMA.DIM_CUSTOMER
        ORDER BY TOTAL_ASSETS DESC
    """).to_pandas()


def get_portfolio_summary(customer_id: str):
    return session.sql(f"""
        SELECT
            ASSET_CLASS,
            SUM(MARKET_VALUE)    AS TOTAL_MV,
            SUM(UNREALIZED_GAIN) AS TOTAL_PL
        FROM SNOWFINANCE_DB.DEMO_SCHEMA.FACT_PORTFOLIO
        WHERE CUSTOMER_ID = '{customer_id}'
        GROUP BY ASSET_CLASS
        ORDER BY TOTAL_MV DESC
    """).to_pandas()


def get_top_holdings(customer_id: str):
    return session.sql(f"""
        SELECT SECURITY_NAME, MARKET_VALUE, UNREALIZED_GAIN_PCT
        FROM SNOWFINANCE_DB.DEMO_SCHEMA.FACT_PORTFOLIO
        WHERE CUSTOMER_ID = '{customer_id}'
        ORDER BY MARKET_VALUE DESC
        LIMIT 5
    """).to_pandas()


def get_analyst_reports(customer_id: str):
    return session.sql(f"""
        SELECT
            ar.PUBLISH_DATE,
            ar.SECURITY_CODE,
            ar.SECURITY_NAME,
            ar.ANALYST_NAME,
            ar.ANALYST_TEAM,
            ar.RATING,
            ar.PREVIOUS_RATING,
            ar.TARGET_PRICE,
            ar.CURRENT_PRICE,
            ar.UPSIDE_PCT,
            ar.REPORT_TITLE,
            ar.EXECUTIVE_SUMMARY
        FROM SNOWFINANCE_DB.DEMO_SCHEMA.ANALYST_REPORTS ar
        INNER JOIN SNOWFINANCE_DB.DEMO_SCHEMA.FACT_PORTFOLIO fp
            ON ar.SECURITY_CODE = fp.SECURITY_CODE
        WHERE fp.CUSTOMER_ID = '{customer_id}'
        ORDER BY ar.PUBLISH_DATE DESC
    """).to_pandas()


@st.cache_data(ttl=300)
def get_news_sentiment_data():
    return session.sql("""
        SELECT
            n.NEWS_ID,
            n.TITLE,
            n.PUBLISH_DATE,
            n.CATEGORY,
            n.IMPORTANCE,
            SNOWFLAKE.CORTEX.AI_SENTIMENT(n.CONTENT):categories[0]:sentiment::VARCHAR AS SENTIMENT_LABEL,
            NULL::FLOAT AS SENTIMENT_SCORE
        FROM SNOWFINANCE_DB.DEMO_SCHEMA.NEWS_ARTICLES n
        ORDER BY CASE n.IMPORTANCE WHEN '高' THEN 1 WHEN '中' THEN 2 ELSE 3 END,
                 n.PUBLISH_DATE DESC
        LIMIT 30
    """).to_pandas()


def run_ai_advice(customer_id: str, customer_name: str, risk: str,
                  total_assets: float, model: str) -> str:
    portfolio_df = get_portfolio_summary(customer_id)
    holdings_df  = get_top_holdings(customer_id)

    portfolio_text = "\n".join([
        f"- {row['ASSET_CLASS']}: {format_oku(row['TOTAL_MV'])} (損益 {format_oku(row['TOTAL_PL'])})"
        for _, row in portfolio_df.iterrows()
    ]) if not portfolio_df.empty else "データなし"

    holdings_text = "\n".join([
        f"- {row['SECURITY_NAME']}: 損益率 {row['UNREALIZED_GAIN_PCT']:+.1f}%"
        for _, row in holdings_df.iterrows()
    ]) if not holdings_df.empty else "データなし"

    prompt = f"""あなたは経験豊富な証券アドバイザーです。
以下の顧客情報を元に、日本語で具体的な投資アドバイスを3点提示してください。
箇条書き形式で簡潔にまとめてください。

【顧客情報】
- 氏名: {customer_name}
- 総資産: {format_oku(total_assets)}
- リスク許容度: {risk}

【ポートフォリオ（アセットクラス別）】
{portfolio_text}

【主要保有銘柄 TOP5】
{holdings_text}
"""
    result = session.sql(f"""
        SELECT SNOWFLAKE.CORTEX.AI_COMPLETE('{model}',
            $${prompt}$$
        ) AS ADVICE
    """).to_pandas()
    raw = result.iloc[0]['ADVICE'] if not result.empty else "アドバイスを取得できませんでした。"
    return clean_ai_output(raw)


st.title("🤖 AI 分析")
st.markdown("Cortex AI による顧客インサイト支援")
st.markdown("---")

customers_df = get_customer_list()

filter_col1, filter_col2, filter_col3 = st.columns([3, 2, 1])
with filter_col1:
    search_query = st.text_input("🔍 顧客名で絞り込み", placeholder="名前を入力...")
with filter_col2:
    risk_options = ["すべて"] + sorted(customers_df['RISK_TOLERANCE'].dropna().unique().tolist())
    risk_filter = st.selectbox("リスク許容度", risk_options)
with filter_col3:
    model_choice = st.selectbox(
        "モデル",
        ["claude-sonnet-4-6", "claude-opus-4-6", "openai-gpt-5.2", "openai-gpt-5.1"],
        index=0
    )
    st.session_state.selected_model = model_choice

filtered_df = customers_df
if search_query:
    filtered_df = filtered_df[filtered_df['CUSTOMER_NAME'].str.contains(search_query, na=False)]
if risk_filter != "すべて":
    filtered_df = filtered_df[filtered_df['RISK_TOLERANCE'] == risk_filter]

if filtered_df.empty:
    st.warning("該当する顧客が見つかりません。検索条件を変更してください。")
    st.stop()

customer_options = {row['CUSTOMER_NAME']: row for _, row in filtered_df.iterrows()}

sel_col, _ = st.columns([3, 1])
with sel_col:
    st.caption(f"{len(customer_options)}名表示中")
    selected_name = st.selectbox("顧客を選択", list(customer_options.keys()))

selected_row = customer_options[selected_name]
selected_id   = selected_row['CUSTOMER_ID']
risk          = selected_row['RISK_TOLERANCE']
total_assets  = selected_row['TOTAL_ASSETS']

st.markdown("---")

tab1, tab2, tab3 = st.tabs(["🤖 投資アドバイス (AI_COMPLETE)", "📊 アナリストレポート", "📰 ニュース感情分析"])

with tab1:
    st.subheader("🤖 AI 投資アドバイス")
    st.markdown(f"**{selected_name}** のポートフォリオを分析して、投資アドバイスを生成します。")

    with st.container():
        col_info1, col_info2, col_info3 = st.columns(3)
        col_info1.metric("顧客", selected_name)
        col_info2.metric("総資産", format_oku(total_assets))
        col_info3.metric("リスク許容度", risk)

    if st.button("💡 AI アドバイスを生成", key="btn_advice", type="primary"):
        with st.spinner(f"{model_choice} でアドバイスを生成中..."):
            advice = run_ai_advice(selected_id, selected_name, risk, total_assets, model_choice)

        with st.container():
            st.markdown("#### 📋 AI アドバイス")
            st.markdown(advice)

    st.info("💡 AI_COMPLETE を使用 — 顧客のポートフォリオ情報をプロンプトに組み込み、パーソナライズされたアドバイスを生成します。")

with tab2:
    st.subheader("📊 アナリストレポート")
    st.markdown(f"**{selected_name}** の保有銘柄に対するアナリスト評価一覧です。")

    reports_df = get_analyst_reports(selected_id)

    if reports_df.empty:
        st.warning("保有銘柄に対するアナリストレポートが見つかりません。")
    else:
        BUY_RATINGS  = {'買い', '強気', 'やや強気'}
        SELL_RATINGS = {'売り', 'やや弱気'}
        RATING_SCORE = {'売り': 1, 'やや弱気': 2, '中立': 3, 'やや強気': 4, '買い': 5, '強気': 5}
        buy_count  = reports_df['RATING'].isin(BUY_RATINGS).sum()
        hold_count = (reports_df['RATING'] == '中立').sum()
        sell_count = reports_df['RATING'].isin(SELL_RATINGS).sum()
        avg_upside = reports_df['UPSIDE_PCT'].mean()

        m1, m2, m3, m4 = st.columns(4)
        m1.metric("レポート件数", f"{len(reports_df)}件")
        m2.metric("買い推奨", f"{buy_count}件", delta=None)
        m3.metric("中立", f"{hold_count}件")
        m4.metric("平均アップサイド", f"{avg_upside:+.1f}%")

        st.markdown("---")

        for _, row in reports_df.iterrows():
            rating     = row['RATING']
            prev       = row['PREVIOUS_RATING']
            upside     = row['UPSIDE_PCT']

            curr_score = RATING_SCORE.get(rating, 3)
            prev_score = RATING_SCORE.get(prev, 3)
            if curr_score > prev_score:
                change_icon = "⬆️ 格上げ"
                rating_color = COLORS['upgrade']
            elif curr_score < prev_score:
                change_icon = "⬇️ 格下げ"
                rating_color = COLORS['downgrade']
            else:
                change_icon = "➡️ 維持"
                rating_color = COLORS['maintain']

            if rating in BUY_RATINGS:
                rating_badge = f"🟢 {rating}"
            elif rating in SELL_RATINGS:
                rating_badge = f"🔴 {rating}"
            else:
                rating_badge = f"⚪ {rating}"

            upside_str  = f"{upside:+.1f}%" if not pd.isna(upside) else "-"
            target_str  = f"¥{int(row['TARGET_PRICE']):,}" if not pd.isna(row['TARGET_PRICE']) else "-"
            current_str = f"¥{int(row['CURRENT_PRICE']):,}" if not pd.isna(row['CURRENT_PRICE']) else "-"

            with st.container():
                head_col, rating_col, price_col = st.columns([4, 2, 3])
                with head_col:
                    st.markdown(f"**{row['SECURITY_NAME']}**　`{row['SECURITY_CODE']}`")
                    st.markdown(f"📝 {row['REPORT_TITLE']}")
                    st.caption(f"{row['PUBLISH_DATE']}　｜　{row['ANALYST_NAME']}（{row['ANALYST_TEAM']}）")
                with rating_col:
                    st.markdown(f"### {rating_badge}")
                    st.caption(f"{prev} → {rating}　{change_icon}")
                with price_col:
                    pc1, pc2 = st.columns(2)
                    pc1.metric("目標株価", target_str)
                    pc2.metric("現在株価", current_str, delta=upside_str)

                if pd.notna(row.get('EXECUTIVE_SUMMARY')) and str(row['EXECUTIVE_SUMMARY']).strip():
                    with st.expander("サマリーを見る"):
                        st.markdown(str(row['EXECUTIVE_SUMMARY']))

with tab3:
    st.subheader("📰 ニュース感情分析")
    st.markdown("直近ニュース30件のAI感情スコア（Cortex AI_SENTIMENT）")

    if st.button("🔍 感情分析を実行", key="btn_sentiment", type="primary"):
        with st.spinner("感情分析を実行中（約30件）..."):
            sentiment_df = get_news_sentiment_data()

        if sentiment_df.empty:
            st.warning("ニュースデータが見つかりません。")
        else:
            pos   = (sentiment_df['SENTIMENT_LABEL'] == 'positive').sum()
            neg   = (sentiment_df['SENTIMENT_LABEL'] == 'negative').sum()
            neut  = len(sentiment_df) - pos - neg
            total = len(sentiment_df)

            m1, m2, m3, m4 = st.columns(4)
            m1.metric("分析件数", f"{total}件")
            m2.metric("🟢 ポジティブ", f"{pos}件", delta=f"{pos/total*100:.0f}%")
            m3.metric("🔴 ネガティブ", f"{neg}件", delta=f"-{neg/total*100:.0f}%", delta_color="inverse")
            m4.metric("⚪ ニュートラル", f"{neut}件")

            st.markdown("---")

            cat_col, dist_col = st.columns([3, 2])

            with cat_col:
                st.markdown("#### カテゴリ別感情分布")
                cat_sentiment = sentiment_df.dropna(subset=['CATEGORY', 'SENTIMENT_LABEL']).groupby(['CATEGORY', 'SENTIMENT_LABEL']).size().reset_index(name='COUNT')
                if not cat_sentiment.empty:
                    color_map = {'positive': COLORS['positive'], 'negative': COLORS['negative'], 'neutral': COLORS['neutral']}
                    fig_cat = px.bar(
                        cat_sentiment,
                        x='CATEGORY', y='COUNT', color='SENTIMENT_LABEL',
                        color_discrete_map=color_map,
                        barmode='stack',
                        height=300
                    )
                    fig_cat.update_layout(margin=dict(l=10, r=10, t=10, b=40),
                                          legend_title_text='感情',
                                          xaxis_title='カテゴリ', yaxis_title='件数')
                    st.plotly_chart(fig_cat, use_container_width=True)

            with dist_col:
                st.markdown("#### 感情スコア分布")
                fig_pie = go.Figure(go.Pie(
                    labels=['ポジティブ', 'ネガティブ', 'ニュートラル'],
                    values=[pos, neg, neut],
                    marker_colors=[COLORS['positive'], COLORS['negative'], COLORS['neutral']],
                    hole=0.45
                ))
                fig_pie.update_layout(height=300, margin=dict(l=10, r=10, t=10, b=10),
                                      showlegend=True)
                st.plotly_chart(fig_pie, use_container_width=True)

            st.markdown("---")
            st.markdown("#### ニュース一覧（重要度・日付順）")

            imp_order = {'高': 0, '中': 1, '低': 2}
            sentiment_df['_IMP_ORDER'] = sentiment_df['IMPORTANCE'].map(imp_order).fillna(9)
            sentiment_df = sentiment_df.sort_values(['_IMP_ORDER', 'PUBLISH_DATE'], ascending=[True, False])

            for _, row in sentiment_df.iterrows():
                lbl   = row.get('SENTIMENT_LABEL', 'neutral')
                score = row.get('SENTIMENT_SCORE', 0.0)
                imp   = str(row.get('IMPORTANCE', ''))

                if lbl == 'positive':
                    badge = "🟢"
                    score_color = COLORS['positive']
                elif lbl == 'negative':
                    badge = "🔴"
                    score_color = COLORS['negative']
                else:
                    badge = "⚪"
                    score_color = COLORS['neutral']

                imp_stars = IMP_STARS_MAP.get(imp, imp)

                with st.container():
                    c1, c2 = st.columns([7, 1])
                    with c1:
                        st.markdown(f"{badge} **{row['TITLE']}**")
                        st.caption(
                            f"📅 {row['PUBLISH_DATE']}　｜　"
                            f"📂 {row.get('CATEGORY', '-')}　｜　"
                            f"重要度: {imp_stars}　｜　"
                            f"感情: **{lbl}**"
                        )
                    with c2:
                        st.markdown(
                            f"<div style='text-align:center;font-size:1.6em'>{badge}</div>",
                            unsafe_allow_html=True
                        )

    st.info("💡 AI_SENTIMENT を使用 — 戻り値: categories[0].sentiment = positive / negative / neutral")

st.markdown("---")
st.caption("💡 ニュースのトレンド分析は「ニュース分析」ページで確認できます。")
