#!/usr/bin/env bash
# install.sh — set up muslim-statusline for Claude Code
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
SETTINGS="$HOME/.claude/settings.json"
STAMP=$(date +%Y-%m-%d-%H%M%S)

PATH="$HOME/.bun/bin:$HOME/.claude/bin:$PATH"   # a jq dropped in ~/.claude/bin wins; see statusline.sh

WINDOWS=false
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) WINDOWS=true ;; esac

# ── Pick the runtime ──
# Bun runs statusline.ts as one native process. The bash script forks for every
# jq/date/git call, and on Windows Claude Code's hard kill of a superseded render
# can land mid-fork: the MSYS child aborts and leaves a bash.exe.stackdump in the
# project directory. So Bun is required there and preferred everywhere else.
BUN=""
if bun --version >/dev/null 2>&1; then
  BUN=$(command -v bun)
  $WINDOWS && BUN=$(cygpath -m "$BUN" 2>/dev/null || echo "$BUN")
fi
if [ -z "$BUN" ]; then
  if $WINDOWS; then
    echo "❌ Bun is required on Windows: https://bun.sh (powershell -c \"irm bun.sh/install.ps1 | iex\")"
    exit 1
  fi
  echo "ℹ️  Bun not found; installing the bash version instead (curl -fsSL https://bun.sh/install | bash to switch later)."
  # Run jq rather than just locating it: a jq that is on PATH but refuses to load
  # passes `command -v` and then fails silently on every render.
  echo '{}' | jq . >/dev/null 2>&1 || { echo "❌ jq is required and must be runnable (brew install jq / sudo apt install jq)"; exit 1; }
  command -v curl >/dev/null 2>&1 || { echo "❌ curl is required"; exit 1; }
fi

if [ -n "$BUN" ]; then
  SRC="$HERE/statusline.ts"; DEST="$HOME/.claude/statuslines/muslim.ts"
  # Quoted so a home directory with a space survives; Claude Code hands the
  # command to a shell, which expands $HOME.
  LINE_CMD="\"$BUN\" \"\$HOME/.claude/statuslines/muslim.ts\""
else
  SRC="$HERE/statusline.sh"; DEST="$HOME/.claude/statuslines/muslim.sh"
  LINE_CMD="bash ~/.claude/statuslines/muslim.sh"
fi
mkdir -p "$HOME/.claude/statuslines"

# ── Back up whatever statusline they run today, before we replace it ──
# 1. An existing install at our destination (either runtime's).
for old in "$HOME/.claude/statuslines/muslim.sh" "$HOME/.claude/statuslines/muslim.ts"; do
  if [ -f "$old" ]; then
    cp "$old" "$old.bak-$STAMP"
    echo "Backed up existing $old → $old.bak-$STAMP"
  fi
done
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
      "$HOME/.claude/statuslines/muslim."*) continue ;;  # already handled above
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
cp "$SRC" "$DEST"
chmod +x "$DEST"
# The other runtime's copy would only confuse the next install; remove it.
if [ -n "$BUN" ]; then rm -f "$HOME/.claude/statuslines/muslim.sh"; else rm -f "$HOME/.claude/statuslines/muslim.ts"; fi

# settings.json is edited with whichever runtime we just picked, so the bash
# path still needs jq but the Bun path does not.
if [ -n "$BUN" ]; then
  edit_settings() { "$BUN" -e '
    const [file, cmd] = process.argv.slice(-2);
    const fs = require("node:fs");
    const s = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, "utf8")) : {};
    s.statusLine = { type: "command", command: cmd };
    fs.writeFileSync(file, JSON.stringify(s, null, 2) + "\n");
  ' "$1" "$2"; }
else
  edit_settings() {
    if [ -f "$1" ]; then
      jq --arg cmd "$2" '.statusLine = {"type":"command","command":$cmd}' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
    else
      jq -n --arg cmd "$2" '{statusLine:{type:"command",command:$cmd}}' > "$1"
    fi
  }
fi

if [ -f "$SETTINGS" ]; then
  cp "$SETTINGS" "$SETTINGS.bak-$STAMP"
  echo "Backed up settings → $SETTINGS.bak-$STAMP"
else
  mkdir -p "$HOME/.claude"
fi
edit_settings "$SETTINGS" "$LINE_CMD"

echo "☪️ Installed ($( [ -n "$BUN" ] && echo bun || echo bash )). Preview:"
preview='{"model":{"display_name":"Claude"},"cwd":"'"$PWD"'","context_window":{"context_window_size":1000000,"current_usage":{"input_tokens":5000,"cache_read_input_tokens":40000}},"cost":{"total_cost_usd":0}}'
if [ -n "$BUN" ]; then echo "$preview" | "$BUN" "$DEST"; else echo "$preview" | bash "$DEST"; fi
echo
echo "Restart Claude Code (or open a new session) to see it."
echo "Optional: set PRAYER_METHOD / PRAYER_LAT / PRAYER_LON / PRAYER_CITY / MS_NO_HIJRI (see README)."
