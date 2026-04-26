"""Clean test fixture for catchai-openclaw contract tests.

No detection layer should fire on this. Used to confirm the contract
test produces an empty/clean envelope (summary.total == 0) without
spurious findings.
"""

import sqlite3


def get_user(uid: int) -> tuple | None:
    conn = sqlite3.connect("users.db")
    cur = conn.cursor()
    # Parameterized query — no SQL injection.
    cur.execute("SELECT id, name, email FROM users WHERE id = ?", (uid,))
    return cur.fetchone()


if __name__ == "__main__":
    print(get_user(1))
