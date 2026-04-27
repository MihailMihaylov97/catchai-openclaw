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

# Capture stdout (the JSON envelope) and stderr (progress chatter)
# separately so we can inspect the envelope without mixing the streams
# the agent reads. Re-emit both at the end in the right places to
# preserve the contract: stdout = openclaw-v1 JSON, stderr = chatter.
OUT_FILE=$(mktemp)
ERR_FILE=$(mktemp)
trap 'rm -f "$OUT_FILE" "$ERR_FILE"' EXIT

run_scan() {
    "${CMD[@]}" > "$OUT_FILE" 2> "$ERR_FILE"
}

run_scan
RC=$?

# catchai uses exit 1 to signal "findings exist that block CI" — that's
# a successful scan with results, not a failure of the tool. Anything
# else is a real binary error and skips the L7 fallback below (no point
# re-running a broken scan).
if [[ $RC -ne 0 && $RC -ne 1 ]]; then
    cat "$ERR_FILE" >&2
    cat "$OUT_FILE"
    echo "error: catchai exited with code $RC" >&2
    exit 4
fi

# Layer 7 fallback: if `flows` mode produced zero L7 findings, re-run
# with `files` mode. flows mode gates LLM calls on L5 taint paths —
# fast and precise on real codebases, but produces nothing when L5
# finds no inter-procedural flows (typical for small projects, single
# files, or codebases without identifiable taint sources/sinks). files
# mode runs the LLM directly on each candidate file and always produces
# *some* signal as long as Anthropic credentials are configured.
#
# We pay for the second pass (extra LLM cost + scan time) only when the
# first pass yielded nothing useful from L7 — exactly the case where the
# extra cost is justified.
#
# `jq` is a soft dependency. Without it we can't inspect the saved
# report, so we skip the fallback rather than guessing.
if [[ "${CATCHAI_SEMANTIC:-1}" != "0" ]] && command -v jq >/dev/null 2>&1; then
    SAVED_REPORT=$(jq -r '.artifacts.json_report // empty' "$OUT_FILE" 2>/dev/null)
    L7_COUNT=0
    if [[ -n "$SAVED_REPORT" && -f "$SAVED_REPORT" ]]; then
        L7_COUNT=$(jq '[.findings[]? | select(.layer=="semantic")] | length' "$SAVED_REPORT" 2>/dev/null || echo 0)
    fi

    if [[ "$L7_COUNT" == "0" ]]; then
        # Swap `flows` → `files` and re-run. The full CMD string-replace is
        # safe because no other token in the array equals "flows".
        CMD=("${CMD[@]/flows/files}")
        echo "L7 fallback: flows mode produced no findings; re-running with --semantic-mode files." >> "$ERR_FILE"
        run_scan
        RC=$?
        if [[ $RC -ne 0 && $RC -ne 1 ]]; then
            cat "$ERR_FILE" >&2
            cat "$OUT_FILE"
            echo "error: catchai exited with code $RC during L7 fallback" >&2
            exit 4
        fi
    fi
fi

cat "$ERR_FILE" >&2
cat "$OUT_FILE"
exit "$RC"
