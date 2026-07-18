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

# ── How Claude Code should invoke bash ──
# On Windows, Git for Windows ships bash.exe in Git\bin but only puts Git\cmd
# on PATH, so a bare "bash" is often unresolvable outside a Git Bash shell.
# Emit an absolute (8.3, space-free) path there; plain "bash" everywhere else.
BASH_CMD="bash"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    _bash_win=$(cygpath -w "$(command -v bash)" 2>/dev/null || true)
    if [ -n "$_bash_win" ]; then
      _bash_short=$(cygpath -d "$_bash_win" 2>/dev/null || true)
      # Claude Code runs the statusline command through Git Bash, where
      # backslashes are escape characters — emit forward slashes instead
      # (cmd.exe and CreateProcess accept them too).
      BASH_CMD=$(cygpath -m "${_bash_short:-$_bash_win}" 2>/dev/null || echo "${_bash_short:-$_bash_win}")
    fi
    ;;
esac

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

  # Candidates, most specific first. Splitting on whitespace alone loses any
  # path containing a space (e.g. C:\Users\So Kanon\...), so try the whole
  # command and the command minus a leading interpreter before falling back to
  # per-token splitting (which still catches glue statuslines chaining scripts).
  # Token 0 is skipped: it is the interpreter (bash, or an absolute bash.exe on
  # Windows), never a statusline script. Backing it up is at best pointless and
  # at worst fatal - cp into Program Files fails, and set -e aborts the install.
  # A bare script path with no interpreter is still covered by "$prev_cmd".
  candidates=()
  if [ -n "$prev_cmd" ]; then
    candidates+=("$prev_cmd" "${prev_cmd#* }")
    read -ra _toks <<< "$prev_cmd" || true
    [ "${#_toks[@]}" -gt 1 ] && candidates+=("${_toks[@]:1}")
  fi

  for tok in ${candidates[@]+"${candidates[@]}"}; do
    p="${tok/#\~/$HOME}"                       # expand a leading ~
    p="${p/\$HOME/$HOME}"                       # expand a literal $HOME
    # Only consider things that actually look like paths. A bare token such as
    # "statusline.sh" would otherwise resolve against the installer's cwd and
    # back up an unrelated file that merely shares the name.
    case "$p" in
      */*|*\\*) ;;
      *) continue ;;
    esac
    [ -L "$p" ] && p=$(readlink -f "$p" 2>/dev/null || echo "$p")  # follow symlinks (e.g. active.sh)
    case "$p" in
      "$DEST"|"$DEST.bak-$STAMP") continue ;;  # don't re-back-up our own target
    esac
    # Never let a best-effort backup abort the install (set -e): an unwritable
    # directory here should warn, not stop the user from installing.
    if [ -f "$p" ] && [ ! -f "$p.bak-$STAMP" ]; then
      if cp "$p" "$p.bak-$STAMP" 2>/dev/null; then
        echo "Backed up current statusline $p → $p.bak-$STAMP"
      else
        echo "⚠️  Could not back up $p (not writable) — continuing"
      fi
    fi
  done
fi

# ── Install the full self-contained script ──
cp "$HERE/statusline.sh" "$DEST"
chmod +x "$DEST"

# Built via --arg so a Windows path's backslashes are JSON-escaped correctly.
LINE_CMD="$BASH_CMD ~/.claude/statuslines/muslim.sh"

if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.bak-$STAMP"
  jq --arg cmd "$LINE_CMD" '.statusLine = {"type":"command","command":$cmd}' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
  echo "Backed up settings → $SETTINGS.bak-$STAMP"
else
  mkdir -p "$HOME/.claude"
  jq -n --arg cmd "$LINE_CMD" '{statusLine:{type:"command",command:$cmd}}' > "$SETTINGS"
fi

echo "☪️ Installed. Preview:"
echo '{"model":{"display_name":"Claude"},"cwd":"'"$PWD"'","context_window":{"context_window_size":1000000,"current_usage":{"input_tokens":5000,"cache_read_input_tokens":40000}},"cost":{"total_cost_usd":0}}' | bash "$HOME/.claude/statuslines/muslim.sh"
echo
echo "Restart Claude Code (or open a new session) to see it."
echo "Optional: set PRAYER_METHOD / PRAYER_LAT / PRAYER_LON / PRAYER_CITY / MS_NO_HIJRI (see README)."
