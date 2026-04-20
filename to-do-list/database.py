import sqlite3
from datetime import date


def get_connection():
    conn = sqlite3.connect("todos.db")
    return conn


def init_db():
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS todos (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            title       TEXT    NOT NULL,
            description TEXT,
            date        TEXT    NOT NULL,
            done        INTEGER DEFAULT 0
        )
    """)
    conn.commit()
    conn.close()


def add_todo(title: str, description: str, todo_date):
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute(
        "INSERT INTO todos (title, description, date) VALUES (?, ?, ?)",
        (title, description, str(todo_date)),
    )
    conn.commit()
    conn.close()


def get_todos_by_date(todo_date):
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM todos WHERE date = ? ORDER BY id", (str(todo_date),))
    rows = cursor.fetchall()
    conn.close()
    return rows


def get_all_todos():
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM todos ORDER BY date, id")
    rows = cursor.fetchall()
    conn.close()
    return rows


def get_today_todos():
    """오늘 날짜의 미완료 할일만 반환 (텔레그램 알림용)"""
    today = date.today().isoformat()
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute(
        "SELECT * FROM todos WHERE date = ? AND done = 0",
        (today,),
    )
    rows = cursor.fetchall()
    conn.close()
    return rows


def mark_done(todo_id: int):
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("UPDATE todos SET done = 1 WHERE id = ?", (todo_id,))
    conn.commit()
    conn.close()


def delete_todo(todo_id: int):
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("DELETE FROM todos WHERE id = ?", (todo_id,))
    conn.commit()
    conn.close()
