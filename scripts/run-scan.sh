#!/usr/bin/env bash
# catchai OpenClaw skill adapter
# ------------------------------
# Thin wrapper the agent calls to invoke `catchai scan` with the
# openclaw-v1 output contract. Handles binary-presence checks, normalises
# exit codes, and writes a small `scan_id` file the agent can quote.
#
# Usage:
#   run-scan.sh <target-directory>
#
# Output: openclaw-v1 JSON to stdout (see ../schema.json).
# Exit codes:
#   0  scan completed (clean OR findings)
#   2  catchai binary not found / not on PATH
#   3  target directory does not exist
#   4  catchai itself crashed (non-clean error from the binary)

set -euo pipefail

TARGET="${1:-}"

if [[ -z "$TARGET" ]]; then
    echo "usage: run-scan.sh <target-directory>" >&2
    exit 64  # EX_USAGE
fi

if [[ ! -d "$TARGET" ]]; then
    echo "error: target directory not found: $TARGET" >&2
    exit 3
fi

if ! command -v catchai >/dev/null 2>&1; then
    cat >&2 <<'EOF'
error: `catchai` not found on PATH.

Install:
  curl -fsSL https://install.catchai.io | bash

Then re-run.
EOF
    exit 2
fi

# Run the scan with the openclaw-v1 envelope. --save persists reports
# to disk so the artifacts block in the output points at real files
# the agent can navigate to.
#
# Layer 7 (semantic / LLM) is on by default in `flows` mode — flows mode
# follows taint paths across functions, which catches the cross-file
# cases that L2/L5 alone miss and which are the whole point of paying
# for an LLM layer. Set `CATCHAI_SEMANTIC=0` to disable for cost/latency
# control (e.g. high-frequency CI use).
#
# Cost note: L7 typically runs $0.50–$2 per scan against current
# Sonnet pricing. If catchai can't find Anthropic credentials, L7 is
# silently skipped with a `layer7-health/missing-credentials` info
# finding rather than failing the scan.
#
# The whole command is built into a single CMD array (always non-empty)
# rather than expanding a separate empty SEMANTIC_FLAG=() array at call
# time. The latter trips `set -u` on bash 3.2 (macOS default; OpenClaw's
# exec shell) — `"${SEMANTIC_FLAG[@]}"` on an empty array fires
# "unbound variable". Building one always-populated array sidesteps the
# whole class of expansion bug.
CMD=(
    catchai scan "$TARGET"
    --output-version openclaw-v1
    --output-top-n "${CATCHAI_TOP_N:-10}"
    --save
)
if [[ "${CATCHAI_SEMANTIC:-1}" != "0" ]]; then
    CMD+=(--semantic --semantic-mode flows)
fi

# stderr is forwarded as-is so the agent sees catchai's progress and
# any stderr-warnings (e.g. the L7 deprecation notice). stdout is the
# JSON envelope.
if ! "${CMD[@]}"; then
    rc=$?
    # catchai uses exit 1 to signal "findings exist that block CI" — that
    # is a successful scan with results, not a failure of the tool itself.
    # Anything else is a real binary error.
    if [[ $rc -ne 1 ]]; then
        echo "error: catchai exited with code $rc" >&2
        exit 4
    fi
fi
