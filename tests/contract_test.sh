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

rc=0
"$REPO_ROOT/scripts/run-scan.sh" "$FIXTURE" >"$OUTPUT" 2>/dev/null || rc=$?
if (( rc != 0 )); then
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
#   - REQUIRED_LAYERS: always shipping in the v0.0.1 baseline
#       L1 (dependency): Trivy/Grype always work on Java
#       L3 (secrets):    gitleaks always works
#   - PENDING_LAYERS_AS_OF: each entry is `layer:min-catchai-version`.
#       Once the installed catchai is >= that version, the layer is
#       enforced as REQUIRED (a 0-finding count fails the test). Until
#       then, missing findings emit an informational warning.
#       This removes the manual "remember to move sast from PENDING to
#       REQUIRED after the release" step that the previous structure
#       silently relied on.
#   - FUTURE_LAYERS: blocked on later phases of the Java parity work
#       L4 (infra):    Phase 2 — Spring config auditor (catchai PR #103)
#       L5 (taint):    Phase 3 — tree-sitter Java callgraph (catchai PR #104)
#   - L7 (semantic): always works in principle but needs Anthropic creds
SAVED=$(jq -r '.artifacts.json_report' "$JAVA_OUTPUT")
[[ -f "$SAVED" ]] || fail "java fixture: saved JSON report missing at $SAVED"

REQUIRED_LAYERS=(dependency secrets)
# layer:min-version pairs — once installed catchai >= min-version, the
# layer is enforced. Add new entries when shipping new Java rules; bump
# the min-version when a PR lands in a tagged catchai release.
#   sast  → 0.0.2  Phase 1.2 SAST rules (catchai PR #87)
#   authz → 0.0.2  Phase 1.3 authz rules (catchai PR #96)
PENDING_LAYERS_AS_OF=(
    "sast:0.0.2"
    "authz:0.0.2"
)
FUTURE_LAYERS=(infra taint)

for layer in "${REQUIRED_LAYERS[@]}"; do
    count=$(jq "[.findings[] | select(.layer==\"$layer\")] | length" "$SAVED")
    if [[ "$count" -lt 1 ]]; then
        fail "java fixture: expected at least 1 $layer finding, got $count"
    fi
    ok "java fixture: $layer found $count finding(s)"
done

# Pending layers — version-gated. If installed catchai is at or past the
# declared min-version, the layer becomes a hard requirement. Until
# then, soft warning only.
#
# Strict format: each entry MUST be exactly two colon-separated fields,
# `layer:semver`. Anything else fails up-front rather than silently
# turning into garbage parsing (e.g. "sast:1.0.0:hotfix" would
# previously become min_version="hotfix" via ${entry##*:} and `sort -V`
# would compare "hotfix" against catchai's real version, with
# unpredictable enforcement).
for entry in "${PENDING_LAYERS_AS_OF[@]}"; do
    # Validate format BEFORE splitting — exactly one colon required.
    colons=$(awk -F: '{print NF-1}' <<<"$entry")
    if [[ "$colons" -ne 1 ]]; then
        fail "PENDING_LAYERS_AS_OF entry '$entry' has $colons colons; expected exactly 1 (format: layer:semver)"
    fi
    IFS=':' read -r layer min_version <<<"$entry"
    if [[ -z "$layer" || -z "$min_version" ]]; then
        fail "PENDING_LAYERS_AS_OF entry '$entry' has empty layer or version"
    fi
    # Validate semver shape (X.Y.Z plus optional -prerelease) — catches
    # the "I forgot a digit" / "I typed 'next'" / "I left a comment in
    # the value" class of bug. Loose check; full semver is overkill.
    if ! [[ "$min_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.+-]+)?$ ]]; then
        fail "PENDING_LAYERS_AS_OF entry '$entry': '$min_version' is not a valid semver"
    fi

    count=$(jq "[.findings[] | select(.layer==\"$layer\")] | length" "$SAVED")
    lower=$(printf '%s\n%s\n' "$min_version" "$ACTUAL_VERSION" | sort -V | head -1)
    if [[ "$lower" == "$min_version" ]]; then
        # ACTUAL_VERSION >= min_version — enforce.
        if [[ "$count" -lt 1 ]]; then
            fail "java fixture: $layer enforced as of catchai $min_version (you have $ACTUAL_VERSION) — got 0 findings"
        fi
        ok "java fixture: $layer found $count finding(s) (enforced as-of $min_version)"
    else
        # ACTUAL_VERSION < min_version — soft.
        if [[ "$count" -lt 1 ]]; then
            echo "  (pending: $layer requires catchai >= $min_version; current $ACTUAL_VERSION — 0 findings is OK for now)" >&2
        else
            ok "java fixture: $layer found $count finding(s) early (will be enforced from $min_version)"
        fi
    fi
done

# Future layers — informational only.
for layer in "${FUTURE_LAYERS[@]}"; do
    count=$(jq "[.findings[] | select(.layer==\"$layer\")] | length" "$SAVED")
    if [[ "$count" -ge 1 ]]; then
        ok "java fixture: $layer found $count finding(s) (future → ready, consider promoting to PENDING_LAYERS_AS_OF)"
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
