# vulnerable-python-app — contract test fixture

Deliberately vulnerable, used by `tests/contract_test.sh` to verify the
catchai openclaw-v1 envelope contract. **Do not run, import, or vendor
into a real project.**

The fixture intentionally avoids "this is a test fixture" markers in
the source files themselves (no docstring disclaimer, no inline
`# vulnerable:` comments) so that L7 (semantic LLM review) treats
the code as if it were production. With those markers present, the
LLM correctly suppresses findings as intentional — which is the right
production behavior but breaks the contract test.

## Expected catchai detections

| Layer | Vulnerability | Where |
|---|---|---|
| L1 (deps) | Vulnerable transitive CVEs in flask, requests, django, pyyaml | `requirements.txt` |
| L2 (sast) | SQL injection via string concat | `app.py:13` (`get_user`) |
| L3 (secrets) | Hardcoded API key | `app.py:7` (`API_KEY`) |
| L7 (semantic) | Path traversal via `os.path.join` absolute-path override | `app.py:18` (`open_project_file`) |

The L7 finding is the load-bearing one: pattern-matching SAST tools
look for `../` traversal sequences and miss the Python-specific
behavior where `os.path.join("/srv/projects", "/etc/passwd", ...)`
discards the prefix because the second argument is absolute. Only L7
catches it.
