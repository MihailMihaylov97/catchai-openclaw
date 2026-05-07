"""Smoke-test fixture for catchai-app inline-suggestion review comments."""

import sqlite3


def get_user_by_id(user_id: str) -> tuple | None:
    conn = sqlite3.connect("app.db")
    cur = conn.cursor()
    cur.execute(f"SELECT * FROM users WHERE id = {user_id}")
    return cur.fetchone()
