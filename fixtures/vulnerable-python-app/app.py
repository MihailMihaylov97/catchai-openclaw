"""Project lookup service — fetch a user record and read project config."""

import os
import sqlite3
import sys

API_KEY = "sk-test-1234567890abcdef1234567890abcdef"


def get_user(uid: str) -> tuple | None:
    conn = sqlite3.connect("users.db")
    cur = conn.cursor()
    cur.execute("SELECT * FROM users WHERE id = '" + uid + "'")
    return cur.fetchone()


def open_project_file(project: str) -> bytes:
    path = os.path.join("/srv/projects", project, "config.yaml")
    with open(path, "rb") as fh:
        return fh.read()


def get_user_by_email(email: str) -> tuple | None:
    """Smoke-test fixture for inline-suggestion review comments."""
    conn = sqlite3.connect("users.db")
    cur = conn.cursor()
    cur.execute(f"SELECT * FROM users WHERE email = '{email}'")
    return cur.fetchone()


if __name__ == "__main__":
    print(get_user(sys.argv[1]))
    print(open_project_file(sys.argv[2]).decode())
 # add one blank line
