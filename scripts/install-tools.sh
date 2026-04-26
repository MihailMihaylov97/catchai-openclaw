#!/usr/bin/env bash
# catchai external tool installer
# -------------------------------
# Some catchai layers shell out to third-party scanners. The catchai
# binary itself is closed-source; this installer is the public glue
# that makes those scanners available on the user's PATH.
#
# Why this is in the public repo, not the binary:
#   - The binary self-reports the tool list via `catchai scan
#     --print-required-tools`. This script asks the binary, then runs
#     the appropriate package-manager install.
#   - Keeping the install logic in bash means users can read it before
#     piping it to bash. The binary tells us *what* to install; this
#     script decides *how*.
#
# Usage:
#   install-tools.sh             # install all recommended tools
#   install-tools.sh --dry-run   # print what would be installed

set -euo pipefail

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=1
fi

# Bail early if catchai itself is not on PATH — without it we cannot
# discover what the user needs.
if ! command -v catchai >/dev/null 2>&1; then
    cat >&2 <<'EOF'
error: `catchai` not found on PATH.

Install catchai first:
  curl -fsSL https://install.catchai.io | bash

Then re-run this script.
EOF
    exit 2
fi

# The binary returns one tool-name per line. Empty output is allowed
# (some configurations need no external tools); we exit cleanly in that
# case rather than failing.
TOOLS_RAW="$(catchai scan --print-required-tools 2>/dev/null || true)"
if [[ -z "$TOOLS_RAW" ]]; then
    echo "catchai reports no external tools required for the current configuration."
    exit 0
fi

# Portable read-into-array. macOS ships bash 3.2 which does NOT
# include ``mapfile``; this loop works on every POSIX-ish bash.
TOOLS=()
while IFS= read -r _line; do
    [[ -n "$_line" ]] && TOOLS+=("$_line")
done <<<"$TOOLS_RAW"

# Detect package manager. Order matters: brew on macOS, apt on Debian,
# pacman on Arch. Anything else falls back to a manual-install message.
PM=""
if command -v brew >/dev/null 2>&1; then
    PM="brew"
elif command -v apt-get >/dev/null 2>&1; then
    PM="apt"
elif command -v pacman >/dev/null 2>&1; then
    PM="pacman"
fi

install_one() {
    local tool="$1"
    if command -v "$tool" >/dev/null 2>&1; then
        echo "✓ $tool already installed"
        return 0
    fi

    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "would install: $tool"
        return 0
    fi

    case "$PM" in
        brew)
            echo "→ brew install $tool"
            brew install "$tool"
            ;;
        apt)
            echo "→ sudo apt-get install -y $tool"
            sudo apt-get install -y "$tool"
            ;;
        pacman)
            echo "→ sudo pacman -S --noconfirm $tool"
            sudo pacman -S --noconfirm "$tool"
            ;;
        *)
            cat >&2 <<EOF
Could not detect a supported package manager (brew/apt/pacman).
Please install '$tool' manually and re-run this script.
EOF
            return 1
            ;;
    esac
}

failed=()
for tool in "${TOOLS[@]}"; do
    [[ -z "$tool" ]] && continue
    install_one "$tool" || failed+=("$tool")
done

if [[ ${#failed[@]} -gt 0 ]]; then
    echo "" >&2
    echo "⚠ Some tools failed to install: ${failed[*]}" >&2
    echo "  catchai will skip the layers that need them and continue with degraded coverage." >&2
    exit 1
fi

echo ""
echo "✓ All required tools installed."
