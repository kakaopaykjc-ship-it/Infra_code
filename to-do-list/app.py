"""
app.py
------
달력형 투두리스트 Streamlit 앱

실행 방법:
    streamlit run app.py
"""

from datetime import date

import pandas as pd
import streamlit as st

from database import (
    add_todo,
    delete_todo,
    get_all_todos,
    get_todos_by_date,
    init_db,
    mark_done,
)

# ── 초기화 ──────────────────────────────────────────────────
init_db()

st.set_page_config(page_title="📅 투두 리스트", layout="wide")
st.title("📅 나의 투두 리스트")

# ── 사이드바: 할일 추가 폼 ────────────────────────────────────
with st.sidebar:
    st.header("➕ 할일 추가")

    new_title = st.text_input("제목 *", placeholder="예) 운동하기")
    new_desc = st.text_area("메모 (선택)", placeholder="예) 헬스장 1시간")
    new_date = st.date_input("날짜", value=date.today())

    if st.button("추가하기 ✅", type="primary", use_container_width=True):
        if new_title.strip():
            add_todo(new_title.strip(), new_desc.strip(), new_date)
            st.success("추가됐어요!")
            st.rerun()
        else:
            st.error("제목을 입력해주세요!")

    st.divider()
    st.caption("💡 notifier.py를 별도 터미널에서 실행하면\n매일 아침 텔레그램 알림을 받을 수 있어요!")

# ── 메인: 날짜별 할일 조회 ─────────────────────────────────────
col_left, col_right = st.columns([1, 2])

with col_left:
    st.subheader("📆 날짜 선택")
    view_date = st.date_input(
        "조회할 날짜",
        value=date.today(),
        key="view_date",
        label_visibility="collapsed",
    )

with col_right:
    st.subheader(f"📋 {view_date.strftime('%Y년 %m월 %d일')} 할 일")
    todos = get_todos_by_date(view_date)

    if not todos:
        st.info("이 날은 할 일이 없어요! 사이드바에서 추가해보세요 ➡️")
    else:
        for todo in todos:
            todo_id, title, desc, todo_date, done = todo

            with st.container():
                c1, c2, c3 = st.columns([0.5, 7, 0.5])

                with c1:
                    if done:
                        st.write("✅")
                    else:
                        if st.button("⬜", key=f"done_{todo_id}", help="완료 체크"):
                            mark_done(todo_id)
                            st.rerun()

                with c2:
                    if done:
                        st.markdown(f"~~{title}~~")
                    else:
                        st.markdown(f"**{title}**")
                    if desc:
                        st.caption(desc)

                with c3:
                    if st.button("🗑️", key=f"del_{todo_id}", help="삭제"):
                        delete_todo(todo_id)
                        st.rerun()

# ── 전체 일정 표 ────────────────────────────────────────────────
st.divider()
st.subheader("📊 전체 일정")

all_todos = get_all_todos()
if not all_todos:
    st.info("아직 등록된 할 일이 없어요!")
else:
    df = pd.DataFrame(all_todos, columns=["ID", "제목", "메모", "날짜", "완료"])
    df["완료"] = df["완료"].map({0: "❌", 1: "✅"})
    df = df.drop(columns=["ID"])
    st.dataframe(df, use_container_width=True, hide_index=True)
