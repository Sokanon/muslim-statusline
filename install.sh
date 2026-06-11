#!/usr/bin/env bash
# install.sh — set up muslim-statusline for Claude Code
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
SETTINGS="$HOME/.claude/settings.json"
STAMP=$(date +%Y-%m-%d-%H%M%S)

command -v jq >/dev/null 2>&1 || { echo "❌ jq is required (brew install jq / sudo apt install jq)"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "❌ curl is required"; exit 1; }

mkdir -p "$HOME/.claude/statuslines"
cp "$HERE/statusline.sh" "$HOME/.claude/statuslines/muslim.sh"
chmod +x "$HOME/.claude/statuslines/muslim.sh"

if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.bak-$STAMP"
  jq '.statusLine = {"type":"command","command":"bash ~/.claude/statuslines/muslim.sh"}' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
  echo "Previous settings backed up to $SETTINGS.bak-$STAMP"
else
  mkdir -p "$HOME/.claude"
  echo '{"statusLine":{"type":"command","command":"bash ~/.claude/statuslines/muslim.sh"}}' > "$SETTINGS"
fi

echo "☪️ Installed. Preview:"
echo '{"model":{"display_name":"Claude"},"cwd":"'"$PWD"'"}' | bash "$HOME/.claude/statuslines/muslim.sh"
echo
echo "Restart Claude Code (or open a new session) to see it."
echo "Optional: set PRAYER_METHOD / PRAYER_LAT / PRAYER_LON / PRAYER_CITY (see README)."
