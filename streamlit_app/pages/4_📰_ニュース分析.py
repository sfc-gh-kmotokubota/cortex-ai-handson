import streamlit as st
import pandas as pd
import plotly.graph_objects as go
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
    'high':     '#DC2626',
    'mid':      '#F59E0B',
    'low':      '#6B7280',
}

IMP_ORDER = ['高', '中', '低']
IMP_COLOR_MAP = {'高': COLORS['high'], '中': COLORS['mid'], '低': COLORS['low']}
IMP_STARS_MAP = {'高': '⭐⭐⭐', '中': '⭐⭐', '低': '⭐'}

session = get_session()


@st.cache_data(ttl=300)
def get_news_with_sentiment(selected_levels: tuple, limit: int):
    level_list = ", ".join([f"'{v}'" for v in selected_levels])
    return session.sql(f"""
        SELECT
            n.NEWS_ID,
            n.TITLE,
            n.PUBLISH_DATE,
            n.IMPORTANCE,
            n.CATEGORY,
            SNOWFLAKE.CORTEX.AI_SENTIMENT(n.CONTENT):categories[0]:sentiment::VARCHAR AS SENTIMENT_LABEL,
            NULL::FLOAT AS SENTIMENT_SCORE
        FROM SNOWFINANCE_DB.DEMO_SCHEMA.NEWS_ARTICLES n
        WHERE n.IMPORTANCE IN ({level_list})
        ORDER BY
            CASE n.IMPORTANCE WHEN '高' THEN 1 WHEN '中' THEN 2 ELSE 3 END,
            n.PUBLISH_DATE DESC
        LIMIT {limit}
    """).to_pandas()


@st.cache_data(ttl=300)
def get_news_stats():
    return session.sql("""
        SELECT
            COUNT(*)                                           AS TOTAL_NEWS,
            COUNT(CASE WHEN IMPORTANCE = '高' THEN 1 END)     AS HIGH_IMP,
            COUNT(CASE WHEN IMPORTANCE = '中' THEN 1 END)     AS MED_IMP,
            COUNT(CASE WHEN IMPORTANCE = '低' THEN 1 END)     AS LOW_IMP,
            COUNT(DISTINCT CATEGORY)                           AS UNIQUE_CATEGORIES
        FROM SNOWFINANCE_DB.DEMO_SCHEMA.NEWS_ARTICLES
    """).to_pandas().iloc[0].to_dict()


@st.cache_data(ttl=300)
def get_importance_distribution():
    return session.sql("""
        SELECT IMPORTANCE, COUNT(*) AS CNT
        FROM SNOWFINANCE_DB.DEMO_SCHEMA.NEWS_ARTICLES
        GROUP BY IMPORTANCE
        ORDER BY CASE IMPORTANCE WHEN '高' THEN 1 WHEN '中' THEN 2 ELSE 3 END
    """).to_pandas()


@st.cache_data(ttl=300)
def get_category_news_count():
    return session.sql("""
        SELECT
            CATEGORY,
            COUNT(*) AS NEWS_COUNT
        FROM SNOWFINANCE_DB.DEMO_SCHEMA.NEWS_ARTICLES
        WHERE CATEGORY IS NOT NULL
        GROUP BY CATEGORY
        ORDER BY NEWS_COUNT DESC
        LIMIT 15
    """).to_pandas()


st.title("📰 ニュース分析")
st.markdown("関連ニュースの重要度・感情分布とカテゴリ別トレンド")
st.markdown("---")

stats = get_news_stats()
importance_dist = get_importance_distribution()
category_news = get_category_news_count()

col1, col2, col3, col4 = st.columns(4)
with col1:
    st.metric("総ニュース数", f"{int(stats.get('TOTAL_NEWS', 0))}件")
with col2:
    st.metric("重要度：高", f"{int(stats.get('HIGH_IMP', 0))}件")
with col3:
    st.metric("重要度：中", f"{int(stats.get('MED_IMP', 0))}件")
with col4:
    st.metric("カテゴリ数", f"{int(stats.get('UNIQUE_CATEGORIES', 0))}カテゴリ")

st.markdown("---")

col_left, col_right = st.columns(2)

with col_left:
    st.subheader("📊 重要度別ニュース件数")
    if not importance_dist.empty:
        imp_colors = [IMP_COLOR_MAP.get(i, COLORS['neutral']) for i in importance_dist['IMPORTANCE'].tolist()]
        fig_imp = go.Figure(go.Bar(
            x=importance_dist['IMPORTANCE'].tolist(),
            y=importance_dist['CNT'].tolist(),
            marker_color=imp_colors,
            text=importance_dist['CNT'].tolist(),
            textposition='outside'
        ))
        fig_imp.update_layout(height=300, margin=dict(l=20, r=20, t=20, b=40),
                               yaxis_title="件数")
        st.plotly_chart(fig_imp, use_container_width=True)

with col_right:
    st.subheader("📈 カテゴリ別ニュース件数")
    if not category_news.empty:
        fig_cat = go.Figure(go.Bar(
            x=category_news['CATEGORY'].tolist(),
            y=category_news['NEWS_COUNT'].tolist(),
            marker_color=COLORS['primary'],
            text=category_news['NEWS_COUNT'].tolist(),
            textposition='outside'
        ))
        fig_cat.update_layout(height=300, margin=dict(l=20, r=20, t=20, b=60),
                               xaxis_tickangle=-45,
                               yaxis_title="件数", xaxis_title="カテゴリ")
        st.plotly_chart(fig_cat, use_container_width=True)

st.markdown("---")

st.subheader("🔍 ニュース感情分析")

col_filter1, col_filter2, col_filter3 = st.columns(3)
with col_filter1:
    selected_levels = st.multiselect(
        "重要度フィルター",
        options=['高', '中', '低'],
        default=['高', '中']
    )
with col_filter2:
    news_limit = st.selectbox("表示件数", [10, 20, 50], index=0)
with col_filter3:
    run_btn = st.button("😊 感情分析を実行", type="primary", use_container_width=True)

if run_btn:
    if not selected_levels:
        st.warning("重要度を1つ以上選択してください。")
    else:
        with st.spinner(f"重要度 {'/'.join(selected_levels)} のニュース {news_limit} 件を分析中..."):
            news_df = get_news_with_sentiment(tuple(selected_levels), news_limit)

        if news_df.empty:
            st.warning("条件に合うニュースが見つかりません。")
        else:
            pos_count  = (news_df['SENTIMENT_LABEL'] == 'positive').sum()
            neg_count  = (news_df['SENTIMENT_LABEL'] == 'negative').sum()
            neut_count = len(news_df) - pos_count - neg_count

            col_s1, col_s2, col_s3, col_s4 = st.columns(4)
            col_s1.metric("分析件数",    f"{len(news_df)}件")
            col_s2.metric("ポジティブ", f"{pos_count}件",  delta=f"{pos_count/len(news_df)*100:.0f}%")
            col_s3.metric("ネガティブ", f"{neg_count}件",  delta=f"-{neg_count/len(news_df)*100:.0f}%", delta_color="inverse")
            col_s4.metric("ニュートラル", f"{neut_count}件")

            col_chart1, col_chart2 = st.columns(2)

            with col_chart1:
                sent_counts = news_df['SENTIMENT_LABEL'].value_counts()
                fig_sent_pie = go.Figure(data=[go.Pie(
                    labels=sent_counts.index.tolist(),
                    values=sent_counts.values.tolist(),
                    hole=0.4,
                    marker_colors=[
                        COLORS['positive'] if lbl == 'positive'
                        else COLORS['negative'] if lbl == 'negative'
                        else COLORS['neutral']
                        for lbl in sent_counts.index.tolist()
                    ]
                )])
                fig_sent_pie.update_layout(
                    title="感情分布",
                    height=280,
                    margin=dict(l=20, r=20, t=40, b=20),
                    legend=dict(orientation="h", yanchor="bottom", y=-0.2)
                )
                st.plotly_chart(fig_sent_pie, use_container_width=True)

            with col_chart2:
                cat_sent = news_df.groupby(['CATEGORY', 'SENTIMENT_LABEL']).size().reset_index(name='CNT')
                if not cat_sent.empty:
                    fig_cat_sent = go.Figure()
                    for lbl, color in [('positive', COLORS['positive']),
                                       ('negative', COLORS['negative']),
                                       ('neutral',  COLORS['neutral'])]:
                        subset = cat_sent[cat_sent['SENTIMENT_LABEL'] == lbl]
                        if not subset.empty:
                            fig_cat_sent.add_trace(go.Bar(
                                name=lbl,
                                x=subset['CATEGORY'].tolist(),
                                y=subset['CNT'].tolist(),
                                marker_color=color
                            ))
                    fig_cat_sent.update_layout(
                        title="カテゴリ別感情分布",
                        barmode='stack',
                        height=280,
                        margin=dict(l=20, r=20, t=40, b=60),
                        xaxis_tickangle=-30,
                        legend=dict(orientation="h", yanchor="bottom", y=-0.5)
                    )
                    st.plotly_chart(fig_cat_sent, use_container_width=True)

            st.markdown("#### 📋 ニュース一覧（感情スコア付き）")
            for _, row in news_df.iterrows():
                lbl   = row.get('SENTIMENT_LABEL', 'neutral')
                score = row.get('SENTIMENT_SCORE', 0.0)
                imp   = str(row.get('IMPORTANCE', ''))
                badge = "🟢" if lbl == 'positive' else "🔴" if lbl == 'negative' else "⚪"
                imp_stars = IMP_STARS_MAP.get(imp, '⭐')

                with st.container(border=True):
                    col_b, col_content = st.columns([1, 9])
                    with col_b:
                        st.markdown(f"## {badge}")
                    with col_content:
                        category = row.get('CATEGORY', '')
                        cat_str = f"  `{category}`" if pd.notna(category) and category else ""
                        st.markdown(f"**{row['TITLE']}**{cat_str}")
                        date_str = str(row.get('PUBLISH_DATE', ''))[:10]
                        st.caption(
                            f"重要度: {imp_stars}（{imp}）  |  感情: **{lbl}**  |  日付: {date_str}"
                        )

st.markdown("---")
st.info("💡 AI_SENTIMENT の戻り値: `{categories:[{name:'overall',sentiment:'positive'/'negative'/'neutral'}]}` — `:categories[0]:sentiment::VARCHAR` でラベル取得")
st.caption("💡 顧客別のニュース感情分析は「AI 分析」ページで確認できます。")
