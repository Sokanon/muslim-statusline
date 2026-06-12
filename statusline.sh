#!/usr/bin/env bash
# muslim-statusline — prayer times, hijri date, and dhikr in your Claude Code statusline
#
# Line 1: model · project@branch · hijri date · city
# Line 2: next prayer + countdown (go-pray window, Jumu'ah, Ramadan iftar/suhoor) · rotating dhikr
#
# APIs (cached aggressively, statusline never blocks on network for long):
#   location: ip-api.com (cached 7 days)        override: PRAYER_LAT / PRAYER_LON / PRAYER_CITY
#   timings:  api.aladhan.com (cached daily)    method:   PRAYER_METHOD (default 3 = MWL; 5 = Egyptian, fits North Africa)
# Test overrides: MS_NOW="HH:MM" fakes the clock, MS_HIJRI_MONTH=9 fakes Ramadan.
# Display: MS_NO_HIJRI=1 hides the hijri date (Ramadan detection still works).

input=$(cat)
command -v jq >/dev/null 2>&1 || { printf "☪️ statusline needs jq"; exit 0; }

green='\033[38;2;120;200;140m'
teal='\033[38;2;100;190;200m'
gold='\033[38;2;230;190;110m'
white='\033[38;2;220;220;220m'
dim='\033[2m'
reset='\033[0m'
sep=" ${dim}·${reset} "

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/muslim-statusline"
mkdir -p "$CACHE"
METHOD="${PRAYER_METHOD:-3}"

# ── Location (IP geolocation, cached 7 days; env overrides win) ──
lat="$PRAYER_LAT"; lon="$PRAYER_LON"; city="$PRAYER_CITY"
if [ -z "$lat" ] || [ -z "$lon" ]; then
  LOC="$CACHE/location.json"
  loc_age=999999999
  [ -s "$LOC" ] && loc_age=$(( $(date +%s) - $(stat -c %Y "$LOC" 2>/dev/null || stat -f %m "$LOC") ))
  if [ "$loc_age" -gt 604800 ]; then
    resp=$(curl -s --max-time 3 "http://ip-api.com/json?fields=status,city,lat,lon" 2>/dev/null)
    # jq 1.6 bug: -e exits 0 on empty input, so guard against an empty response
    [ -n "$resp" ] && echo "$resp" | jq -e '.status=="success"' >/dev/null 2>&1 && echo "$resp" > "$LOC"
  fi
  if [ -s "$LOC" ]; then
    lat=$(jq -r '.lat' "$LOC"); lon=$(jq -r '.lon' "$LOC")
    [ -z "$city" ] && city=$(jq -r '.city // empty' "$LOC")
  fi
fi

# ── Prayer timings (Aladhan, cached per day; fetch throttled to 1/min on failure) ──
key="$(date +%F)-m$METHOD"
TIM="$CACHE/timings-$key.json"
STAMP="$CACHE/fetch-attempt"
# self-heal: a cache file that doesn't parse poisons the whole day — drop it so it refetches
# (check the extracted value, not jq's exit code: jq 1.6 -e exits 0 on empty/whitespace input)
[ -s "$TIM" ] && [ -z "$(jq -r '.data.timings.Fajr // empty' "$TIM" 2>/dev/null)" ] && rm -f "$TIM"
if [ ! -s "$TIM" ] && [ -n "$lat" ] && [ -n "$lon" ]; then
  stamp_age=999999
  [ -f "$STAMP" ] && stamp_age=$(( $(date +%s) - $(stat -c %Y "$STAMP" 2>/dev/null || stat -f %m "$STAMP") ))
  if [ "$stamp_age" -ge 60 ]; then
    touch "$STAMP"
    resp=$(curl -s --max-time 4 "https://api.aladhan.com/v1/timings/$(date +%d-%m-%Y)?latitude=$lat&longitude=$lon&method=$METHOD" 2>/dev/null)
    if [ -n "$resp" ] && echo "$resp" | jq -e '.data.timings.Fajr' >/dev/null 2>&1; then
      echo "$resp" > "$TIM"
      find "$CACHE" -name 'timings-*.json' ! -name "timings-$key.json" -delete 2>/dev/null
    fi
  fi
fi

# ── Dhikr rotation (changes every 30 minutes) ──
adhkar=(
  "سبحان الله وبحمده — SubhanAllahi wa bihamdihi"
  "لا إله إلا الله — La ilaha illa Allah"
  "الحمد لله — Alhamdulillah"
  "الله أكبر — Allahu Akbar"
  "أستغفر الله — Astaghfirullah"
  "لا حول ولا قوة إلا بالله — La hawla wa la quwwata illa billah"
  "اللهم صل على محمد ﷺ — Salawat upon the Prophet ﷺ"
  "سبحان الله العظيم — SubhanAllahil-Adheem"
  "حسبنا الله ونعم الوكيل — Hasbunallahu wa ni'mal wakeel"
  "رب اغفر لي — Rabbi-ghfir li"
)
didx=$(( $(date +%s) / 1800 % ${#adhkar[@]} ))
dhikr="${adhkar[$didx]}"

# ── Clock (MS_NOW override for testing) ──
now_hm="${MS_NOW:-$(date +%H:%M)}"
now_min=$(( 10#${now_hm%%:*} * 60 + 10#${now_hm##*:} ))

# ── Next prayer ──
prayer_line=""
hijri=""
if [ -s "$TIM" ]; then
  hijri_day=$(jq -r '.data.date.hijri.day' "$TIM")
  hijri_month=$(jq -r '.data.date.hijri.month.en' "$TIM")
  hijri_year=$(jq -r '.data.date.hijri.year' "$TIM")
  hijri_mnum="${MS_HIJRI_MONTH:-$(jq -r '.data.date.hijri.month.number' "$TIM")}"
  hijri="${hijri_day} ${hijri_month} ${hijri_year}"

  names=(Fajr Dhuhr Asr Maghrib Isha)
  next_name=""; next_min=99999; prev_name=""; prev_min=-99999
  for p in "${names[@]}"; do
    t=$(jq -r ".data.timings.$p" "$TIM" | cut -c1-5)
    m=$(( 10#${t%%:*} * 60 + 10#${t##*:} ))
    if [ "$m" -gt "$now_min" ] && [ "$m" -lt "$next_min" ]; then next_name="$p"; next_min=$m; next_t="$t"; fi
    if [ "$m" -le "$now_min" ] && [ "$m" -gt "$prev_min" ]; then prev_name="$p"; prev_min=$m; fi
  done
  if [ -z "$next_name" ]; then  # past Isha → Fajr tomorrow (approximate with today's time)
    next_name="Fajr"; next_t=$(jq -r '.data.timings.Fajr' "$TIM" | cut -c1-5)
    next_min=$(( 10#${next_t%%:*} * 60 + 10#${next_t##*:} + 1440 ))
  fi

  diff=$(( next_min - now_min ))
  if [ "$diff" -ge 60 ]; then cd_str="in $(( diff / 60 ))h $(( diff % 60 ))m"; else cd_str="in ${diff}m"; fi

  label="$next_name"
  [ "$(date +%u)" -eq 5 ] && [ "$next_name" = "Dhuhr" ] && label="Jumu'ah 🕌"

  if [ -n "$prev_name" ] && [ $(( now_min - prev_min )) -le 20 ]; then
    prayer_line="${gold}🤲 ${prev_name} time — go pray${reset}"
  elif [ "$hijri_mnum" = "9" ] && [ "$next_name" = "Maghrib" ]; then
    prayer_line="${gold}🌙 iftar ${cd_str} (${next_t})${reset}"
  elif [ "$hijri_mnum" = "9" ] && [ "$next_name" = "Fajr" ] || { [ "$hijri_mnum" = "9" ] && [ "$prev_name" = "" ]; }; then
    prayer_line="${gold}🌙 suhoor ends at Fajr ${next_t} (${cd_str})${reset}"
  else
    prayer_line="${green}🕌 ${label} ${next_t}${reset} ${dim}(${cd_str})${reset}"
  fi
fi

# ── Embed mode: single line (prayer · hijri · dhikr), no session info ──
# For composing with an existing statusline:  echo "$input" | MS_LINE_ONLY=1 bash muslim.sh
if [ -n "$MS_LINE_ONLY" ]; then
  out=""
  [ -n "$prayer_line" ] && out="$prayer_line"
  [ -n "$hijri" ] && [ -z "$MS_NO_HIJRI" ] && { [ -n "$out" ] && out+="$sep"; out+="${gold}☪️ ${hijri}${reset}"; }
  [ -n "$out" ] && out+="$sep"; out+="${teal}📿 ${dhikr}${reset}"
  printf "%b" "$out"
  exit 0
fi

# ── Session info ──
model=$(echo "$input" | jq -r '.model.display_name // "Claude"')
cwd=$(echo "$input" | jq -r '.cwd // empty')
dir="${cwd##*/}"
branch=$(git -C "${cwd:-.}" rev-parse --abbrev-ref HEAD 2>/dev/null)

line1="${white}${model}${reset}"
[ -n "$dir" ] && { line1+="${sep}${teal}${dir}${reset}"; [ -n "$branch" ] && line1+="${dim}@${reset}${teal}${branch}${reset}"; }
[ -n "$hijri" ] && [ -z "$MS_NO_HIJRI" ] && line1+="${sep}${gold}☪️ ${hijri}${reset}"
[ -n "$city" ] && line1+="${sep}${dim}${city}${reset}"

if [ -n "$prayer_line" ]; then
  line2="${prayer_line}${sep}${teal}📿 ${dhikr}${reset}"
else
  line2="${teal}📿 ${dhikr}${reset}"   # offline / no cache yet — dhikr still works
fi

printf "%b\n%b" "$line1" "$line2"
