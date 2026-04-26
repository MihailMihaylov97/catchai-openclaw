"""Vulnerable test fixture for catchai-openclaw contract tests.

Deliberately contains issues each catchai layer should detect:
  - L1 (deps): outdated flask/requests/django/pyyaml in requirements.txt
  - L2 (sast): SQL injection via string concat
  - L3 (secrets): hardcoded API key
  - L7 (semantic): path traversal via unvalidated CLI argument

Do not run. Do not import. Do not vendor into a real project.
"""

import os
import sqlite3
import sys

API_KEY = "sk-test-1234567890abcdef1234567890abcdef"  # L3: hardcoded secret


def get_user(uid: str) -> tuple | None:
    conn = sqlite3.connect("users.db")
    cur = conn.cursor()
    # L2: SQL injection — string concat into a query.
    cur.execute("SELECT * FROM users WHERE id = '" + uid + "'")
    return cur.fetchone()


def open_project_file(project: str) -> bytes:
    # L7: path traversal — `project` is unvalidated CLI input joined
    # straight into a filesystem path with no allow-list.
    path = os.path.join("/srv/projects", project, "config.yaml")
    with open(path, "rb") as fh:
        return fh.read()


if __name__ == "__main__":
    print(get_user(sys.argv[1]))
    print(open_project_file(sys.argv[2]).decode())
