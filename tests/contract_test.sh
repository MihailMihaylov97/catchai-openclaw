#!/usr/bin/env bash
# Contract test for the openclaw-v1 envelope.
# -------------------------------------------
# Validates that:
#   1. run-scan.sh executes without crashing on a known-vulnerable fixture
#   2. The output is well-formed JSON
#   3. The output validates against schema.json
#   4. SKILL.md frontmatter parses as valid YAML
#   5. SKILL.md declares min_catchai_version that matches the binary
#
# Run:
#   tests/contract_test.sh
#
# Requires: catchai on PATH, jq, python3 (for jsonschema validation), yq

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEMA="$REPO_ROOT/schema.json"
FIXTURE="$REPO_ROOT/fixtures/vulnerable-python-app"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

ok() {
    echo "✓ $*"
}

# ----- precheck -----------------------------------------------------------

command -v catchai >/dev/null 2>&1 || fail "catchai not on PATH"
command -v jq >/dev/null 2>&1 || fail "jq is required (brew install jq / apt install jq)"
command -v python3 >/dev/null 2>&1 || fail "python3 is required for schema validation"

[[ -d "$FIXTURE" ]] || fail "fixture missing: $FIXTURE"
[[ -f "$SCHEMA" ]] || fail "schema missing: $SCHEMA"

# ----- 1. run the adapter -------------------------------------------------

OUTPUT="$(mktemp)"
trap 'rm -f "$OUTPUT"' EXIT

if ! "$REPO_ROOT/scripts/run-scan.sh" "$FIXTURE" >"$OUTPUT" 2>/dev/null; then
    rc=$?
    fail "run-scan.sh exited with $rc on $FIXTURE"
fi
ok "run-scan.sh exited 0"

# ----- 2. valid JSON ------------------------------------------------------

if ! jq -e . "$OUTPUT" >/dev/null 2>&1; then
    fail "output is not valid JSON"
fi
ok "output is valid JSON"

# ----- 3. schema validation -----------------------------------------------

python3 - "$OUTPUT" "$SCHEMA" <<'PY'
import json
import sys

try:
    import jsonschema
except ImportError:
    print("install jsonschema: pip install jsonschema", file=sys.stderr)
    sys.exit(1)

with open(sys.argv[1]) as f:
    payload = json.load(f)
with open(sys.argv[2]) as f:
    schema = json.load(f)

try:
    jsonschema.validate(payload, schema)
except jsonschema.ValidationError as exc:
    print(f"FAIL: schema validation: {exc.message}", file=sys.stderr)
    print(f"path: {list(exc.absolute_path)}", file=sys.stderr)
    sys.exit(1)
PY
ok "output matches schema.json"

# ----- 4. SKILL.md frontmatter parses as YAML -----------------------------

# Extract frontmatter (between first two --- lines) and try parsing.
python3 - "$REPO_ROOT/SKILL.md" <<'PY'
import sys

try:
    import yaml
except ImportError:
    print("install pyyaml: pip install pyyaml", file=sys.stderr)
    sys.exit(1)

with open(sys.argv[1]) as f:
    text = f.read()

if not text.startswith("---\n"):
    print("FAIL: SKILL.md missing frontmatter", file=sys.stderr)
    sys.exit(1)

end = text.find("\n---\n", 4)
if end == -1:
    print("FAIL: SKILL.md frontmatter not closed", file=sys.stderr)
    sys.exit(1)

front = text[4:end]
try:
    meta = yaml.safe_load(front)
except yaml.YAMLError as exc:
    print(f"FAIL: SKILL.md frontmatter not valid YAML: {exc}", file=sys.stderr)
    sys.exit(1)

# Required fields the OpenClaw skill loader reads.
for key in ("name", "description", "metadata"):
    if key not in meta:
        print(f"FAIL: SKILL.md frontmatter missing '{key}'", file=sys.stderr)
        sys.exit(1)

oc = meta.get("metadata", {}).get("openclaw", {})
for key in ("min_catchai_version", "output_version", "requires"):
    if key not in oc:
        print(f"FAIL: SKILL.md openclaw metadata missing '{key}'", file=sys.stderr)
        sys.exit(1)

if oc["output_version"] != "openclaw-v1":
    print(f"FAIL: output_version should be 'openclaw-v1', got {oc['output_version']!r}", file=sys.stderr)
    sys.exit(1)
PY
ok "SKILL.md frontmatter is valid + complete"

# ----- 5. min_catchai_version compatibility check -------------------------

DECLARED_MIN="$(python3 -c "
import yaml
text = open('$REPO_ROOT/SKILL.md').read()
front = text[4:text.find(chr(10) + '---' + chr(10), 4)]
print(yaml.safe_load(front)['metadata']['openclaw']['min_catchai_version'])
")"

ACTUAL_VERSION="$(catchai --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"

if [[ -z "$ACTUAL_VERSION" ]]; then
    fail "could not parse 'catchai --version' output"
fi

# Simple semver comparison via sort -V.
LOWEST="$(printf '%s\n%s\n' "$DECLARED_MIN" "$ACTUAL_VERSION" | sort -V | head -1)"
if [[ "$LOWEST" != "$DECLARED_MIN" ]]; then
    fail "installed catchai $ACTUAL_VERSION is older than SKILL.md min $DECLARED_MIN"
fi
ok "catchai $ACTUAL_VERSION ≥ declared min $DECLARED_MIN"

# ----- 6. Java fixture: same envelope checks + per-layer presence ---------
#
# Phase 4 of the Java parity work (docs/dev/CATCHAI_Java_4.md in the
# catchai source repo). The Java code path goes through different
# rules (L2 Java SAST, L6 Java authz) than Python; without this fixture
# in CI, regressions in the Java path land silently.
#
# The per-layer ≥ 1 check is the regression net. If a future PR breaks
# any layer's Java coverage, this test fails immediately and loudly:
# "expected at least 1 X finding, got 0".

JAVA_FIXTURE="$REPO_ROOT/fixtures/vulnerable-java-app"
JAVA_OUTPUT="$(mktemp)"

[[ -d "$JAVA_FIXTURE" ]] || fail "java fixture missing: $JAVA_FIXTURE"

# catchai exits 1 to signal "blocking findings exist" — that's success
# from our perspective. Only exit codes >= 2 indicate real binary errors.
# `set -e` is in effect, so we capture the exit via `|| true` and check
# the value separately rather than letting the script abort.
java_rc=0
"$REPO_ROOT/scripts/run-scan.sh" "$JAVA_FIXTURE" >"$JAVA_OUTPUT" 2>/dev/null || java_rc=$?
if [[ $java_rc -ne 0 && $java_rc -ne 1 ]]; then
    fail "run-scan.sh exited with $java_rc on Java fixture (binary error)"
fi
ok "java run-scan.sh exited $java_rc"

if ! jq -e . "$JAVA_OUTPUT" >/dev/null 2>&1; then
    fail "java fixture output is not valid JSON"
fi
ok "java fixture output is valid JSON"

python3 - "$JAVA_OUTPUT" "$SCHEMA" <<'PY'
import json
import sys

import jsonschema

with open(sys.argv[1]) as f:
    payload = json.load(f)
with open(sys.argv[2]) as f:
    schema = json.load(f)

try:
    jsonschema.validate(payload, schema)
except jsonschema.ValidationError as exc:
    print(f"FAIL: java fixture schema validation: {exc.message}", file=sys.stderr)
    sys.exit(1)
PY
ok "java fixture matches openclaw-v1 schema"

# Per-layer presence — each REQUIRED layer must contribute ≥ 1 finding
# to the saved report. top_findings is cap-limited by the renderer; the
# saved report has the full list.
#
# Layers split by current binary readiness (v0.0.1 baseline):
#   - REQUIRED_LAYERS:    always shipping in the v0.0.1 baseline
#       L1 (dependency): Trivy/Grype always work on Java
#       L3 (secrets):    gitleaks always works
#   - PENDING_LAYERS: present in dev but not in the released binary;
#                     promote to REQUIRED once v0.0.2 ships
#       L2 (sast):  Phase 1.2 rules merged in PR #87, awaiting release
#       L6 (authz): Phase 1.3 rules merged in PR #96, awaiting release
#   - FUTURE_LAYERS: blocked on later phases of the Java parity work
#       L4 (infra):    Phase 2 (Spring config auditor) — not built
#       L5 (taint):    Phase 3 (tree-sitter Java callgraph) — not built
#   - L7 (semantic): always works in principle but needs Anthropic creds
SAVED=$(jq -r '.artifacts.json_report' "$JAVA_OUTPUT")
[[ -f "$SAVED" ]] || fail "java fixture: saved JSON report missing at $SAVED"

REQUIRED_LAYERS=(dependency secrets)
PENDING_LAYERS=(sast authz)
FUTURE_LAYERS=(infra taint)

for layer in "${REQUIRED_LAYERS[@]}"; do
    count=$(jq "[.findings[] | select(.layer==\"$layer\")] | length" "$SAVED")
    if [[ "$count" -lt 1 ]]; then
        fail "java fixture: expected at least 1 $layer finding, got $count"
    fi
    ok "java fixture: $layer found $count finding(s)"
done

# Pending layers — warn if missing but don't fail the test. Promote each
# entry to REQUIRED_LAYERS in the same PR that ships the corresponding
# binary release.
for layer in "${PENDING_LAYERS[@]}"; do
    count=$(jq "[.findings[] | select(.layer==\"$layer\")] | length" "$SAVED")
    if [[ "$count" -lt 1 ]]; then
        echo "  (warn: $layer found 0 findings — pending v0.0.2 release; promote to REQUIRED after release)" >&2
    else
        ok "java fixture: $layer found $count finding(s) (pending → ready, promote to REQUIRED)"
    fi
done

# Future layers — informational only.
for layer in "${FUTURE_LAYERS[@]}"; do
    count=$(jq "[.findings[] | select(.layer==\"$layer\")] | length" "$SAVED")
    if [[ "$count" -ge 1 ]]; then
        ok "java fixture: $layer found $count finding(s) (future → ready, promote to REQUIRED)"
    fi
done

# L7 — best-effort, requires Anthropic credentials.
l7_count=$(jq "[.findings[] | select(.layer==\"semantic\" and .severity != \"info\")] | length" "$SAVED")
l7_skipped=$(jq "[.findings[] | select(.rule_id == \"layer7-health/missing-credentials\")] | length" "$SAVED")
if [[ "$l7_skipped" -gt 0 ]]; then
    echo "  (L7 skipped — no Anthropic credentials configured)" >&2
elif [[ "$l7_count" -lt 1 ]]; then
    echo "  (warn: L7 ran but produced no semantic findings — typical for v0.0.1 on Java)" >&2
else
    ok "java fixture: semantic found $l7_count finding(s)"
fi

# Cleanup the second temp file
rm -f "$JAVA_OUTPUT"

echo ""
echo "All contract checks passed."
