#!/bin/bash
# cc-statusline installer.
# Usage: wget -qO- https://raw.githubusercontent.com/tkr41850-debug/claude-code-utils/main/statusline/install.sh | bash
#    or: curl -fsSL https://raw.githubusercontent.com/tkr41850-debug/claude-code-utils/main/statusline/install.sh | bash

set -euo pipefail

REPO="https://raw.githubusercontent.com/tkr41850-debug/claude-code-utils/main/statusline"
SCRIPT_URL="$REPO/cc-statusline.sh"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
TARGET="$CLAUDE_DIR/cc-statusline.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

# 1. Dependency check
say "Checking dependencies"
missing=()
for bin in jq awk git find; do
  command -v "$bin" >/dev/null 2>&1 || missing+=("$bin")
done
if [ ${#missing[@]} -gt 0 ]; then
  die "Missing required tools: ${missing[*]}. Install them and re-run."
fi

# 2. Pick a downloader
if   command -v curl >/dev/null 2>&1; then DL="curl -fsSL"
elif command -v wget >/dev/null 2>&1; then DL="wget -qO-"
else die "Neither curl nor wget found."
fi

# 3. Ensure target dir
mkdir -p "$CLAUDE_DIR"

# 4. Download script
say "Fetching cc-statusline.sh → $TARGET"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
if ! $DL "$SCRIPT_URL" >"$TMP"; then
  die "Failed to fetch $SCRIPT_URL"
fi
[ -s "$TMP" ] || die "Downloaded file is empty"
head -1 "$TMP" | grep -q '^#!' || die "Downloaded file does not look like a shell script"

# Backup existing script if present and different
if [ -f "$TARGET" ] && ! cmp -s "$TMP" "$TARGET"; then
  BAK="$TARGET.bak.$(date +%Y%m%d-%H%M%S)"
  cp "$TARGET" "$BAK"
  say "Existing script backed up → $BAK"
fi

mv "$TMP" "$TARGET"
chmod +x "$TARGET"
trap - EXIT

# 5. Update settings.json
NEW_CMD="bash \"$TARGET\""
if [ -f "$SETTINGS" ]; then
  if ! jq empty "$SETTINGS" >/dev/null 2>&1; then
    die "$SETTINGS is not valid JSON. Aborting before clobbering it."
  fi
  CURRENT_CMD=$(jq -r '.statusLine.command // ""' "$SETTINGS")
  if [ "$CURRENT_CMD" = "$NEW_CMD" ]; then
    say "settings.json already configured. Done."
    exit 0
  fi
  BAK="$SETTINGS.bak.$(date +%Y%m%d-%H%M%S)"
  cp "$SETTINGS" "$BAK"
  say "Backed up settings.json → $BAK"
  jq --arg cmd "$NEW_CMD" \
     '.statusLine = {type: "command", command: $cmd}' \
     "$SETTINGS" > "$SETTINGS.tmp"
  mv "$SETTINGS.tmp" "$SETTINGS"
else
  say "Creating $SETTINGS"
  jq -n --arg cmd "$NEW_CMD" \
    '{statusLine: {type: "command", command: $cmd}}' > "$SETTINGS"
fi

# 6. Done
cat <<EOF

\033[1;32m✓ cc-statusline installed.\033[0m

Restart Claude Code to see the new statusline.

Files:
  - $TARGET
  - $SETTINGS

Optional env:
  CLAUDE_AUTOCOMPACT_TOKENS=200000   # pin auto-compact threshold

Repo: https://github.com/tkr41850-debug/claude-code-utils
EOF
