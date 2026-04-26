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

echo ""
echo "All contract checks passed."
