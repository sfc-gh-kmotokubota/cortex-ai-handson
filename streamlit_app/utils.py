import os
import streamlit as st

@st.cache_resource
def get_session():
    try:
        from snowflake.snowpark.context import get_active_session
        return get_active_session()
    except Exception:
        from snowflake.snowpark import Session
        connection_name = os.getenv("SNOWFLAKE_CONNECTION_NAME", "KMOT_AWS1")
        return Session.builder.config("connection_name", connection_name).create()
