#!/usr/bin/env bash
# install.sh — set up muslim-statusline for Claude Code
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
SETTINGS="$HOME/.claude/settings.json"
STAMP=$(date +%Y-%m-%d-%H%M%S)

command -v jq >/dev/null 2>&1 || { echo "❌ jq is required (brew install jq / sudo apt install jq)"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "❌ curl is required"; exit 1; }

DEST="$HOME/.claude/statuslines/muslim.sh"
mkdir -p "$HOME/.claude/statuslines"

# ── Back up whatever statusline they run today, before we replace it ──
# 1. An existing install at our destination.
if [ -f "$DEST" ]; then
  cp "$DEST" "$DEST.bak-$STAMP"
  echo "Backed up existing $DEST → $DEST.bak-$STAMP"
fi
# 2. Best-effort: every script their current statusLine command references.
#    Covers glue/wrapper statuslines that chain several scripts, not just one.
if [ -f "$SETTINGS" ]; then
  prev_cmd=$(jq -r '.statusLine.command // empty' "$SETTINGS" 2>/dev/null)
  for tok in $prev_cmd; do
    p="${tok/#\~/$HOME}"                       # expand a leading ~
    p="${p/\$HOME/$HOME}"                       # expand a literal $HOME
    [ -L "$p" ] && p=$(readlink -f "$p" 2>/dev/null || echo "$p")  # follow symlinks (e.g. active.sh)
    case "$p" in
      "$DEST"|"$DEST.bak-$STAMP") continue ;;  # don't re-back-up our own target
    esac
    if [ -f "$p" ] && [ ! -f "$p.bak-$STAMP" ]; then
      cp "$p" "$p.bak-$STAMP"
      echo "Backed up current statusline $p → $p.bak-$STAMP"
    fi
  done
fi

# ── Install the full self-contained script ──
cp "$HERE/statusline.sh" "$DEST"
chmod +x "$DEST"

if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.bak-$STAMP"
  jq '.statusLine = {"type":"command","command":"bash ~/.claude/statuslines/muslim.sh"}' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
  echo "Backed up settings → $SETTINGS.bak-$STAMP"
else
  mkdir -p "$HOME/.claude"
  echo '{"statusLine":{"type":"command","command":"bash ~/.claude/statuslines/muslim.sh"}}' > "$SETTINGS"
fi

echo "☪️ Installed. Preview:"
echo '{"model":{"display_name":"Claude"},"cwd":"'"$PWD"'","context_window":{"context_window_size":1000000,"current_usage":{"input_tokens":5000,"cache_read_input_tokens":40000}},"cost":{"total_cost_usd":0}}' | bash "$HOME/.claude/statuslines/muslim.sh"
echo
echo "Restart Claude Code (or open a new session) to see it."
echo "Optional: set PRAYER_METHOD / PRAYER_LAT / PRAYER_LON / PRAYER_CITY / MS_NO_HIJRI (see README)."
