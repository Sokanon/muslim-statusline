# ☪️ muslim-statusline

Prayer times and dhikr stacked on a usage statusline (context, cost, plan limits) for Claude Code — one script, three lines.

```
🕌 Maghrib 19:50 (in 2h 25m) · 📿 سبحان الله وبحمده — SubhanAllahi wa bihamdihi
Opus 4.8 | my-project@master (+469 -25)
ctx 45k/1.0m (4%) | cost $1.23 | 5h 9% | 7d 5% | extra $0.00/$200.00
```

<sub>Hijri date sits between the prayer and the dhikr by default; hidden above via `MS_NO_HIJRI=1`.</sub>

## What it does

**Line 1 — faith:**

- **Next prayer with countdown** — and for 20 minutes after the adhan: `🤲 Asr time — go pray`
- **Jumu'ah** — Friday's Dhuhr is labeled `Jumu'ah 🕌`
- **Ramadan mode** — automatic during the hijri month: iftar countdown through the day, suhoor deadline before Fajr
- **Hijri date** (hide with `MS_NO_HIJRI=1`)
- **Dhikr** — rotates every 30 minutes through 10 adhkar (Arabic + transliteration)
- Works offline once cached: location is fetched weekly ([ip-api.com](http://ip-api.com)), prayer times once per day ([Aladhan API](https://aladhan.com/prayer-times-api)). No API keys. If the network is down, dhikr still shows.

**Lines 2–3 — usage:** model · repo@branch with diff stats, then context window, session cost, and your 5h / 7d / extra-usage limits (cached 60s from the Claude OAuth usage API). This half is adapted from [claude-code-statusline](https://github.com/aleksander-dytko/claude-code-statusline) by Aleksander Dytko (MIT) and folded into the same script. Set `STATUSLINE_SHOW_*=false` to hide any segment — see the config block at the top of `statusline.sh`.

## Install

```bash
git clone https://github.com/Sokanon/muslim-statusline.git
cd muslim-statusline
bash install.sh
```

Or tell Claude Code: *"Clone https://github.com/Sokanon/muslim-statusline and run its install.sh"*

The installer drops a single self-contained `~/.claude/statuslines/muslim.sh` and points your statusline at it. It backs up anything it would replace first — your `settings.json` and whatever statusline script you currently run — to timestamped `.bak-<date>` files, so you can always restore.

Requirements: `jq`, `curl`, GNU date (on macOS: `brew install coreutils`).

## Configuration (optional)

Set these in the `env` block of `~/.claude/settings.json` (or export them):

| Variable | Default | Notes |
|---|---|---|
| `PRAYER_METHOD` | `3` (Muslim World League) | `5` = Egyptian (fits North Africa), `4` = Umm al-Qura, `2` = ISNA — [full list](https://aladhan.com/calculation-methods) |
| `PRAYER_LAT` / `PRAYER_LON` | auto via IP | set if IP geolocation is off (VPN, datacenter IP) |
| `PRAYER_CITY` | auto via IP | display name only |
| `MS_NO_HIJRI` | unset | set to `1` to hide the hijri date (Ramadan detection still works) |

Note: countdowns use your machine's clock, so your system timezone should match your physical location. If you're on a VPN, set `PRAYER_LAT`/`PRAYER_LON` manually.

## Composing with an existing statusline

Already have a statusline you like? `MS_LINE_ONLY=1` outputs just one line (prayer · hijri · dhikr) so you can stack it on top of yours:

```bash
#!/usr/bin/env bash
input=$(cat)
prayer=$(printf '%s' "$input" | MS_LINE_ONLY=1 bash ~/.claude/statuslines/muslim.sh)
base=$(printf '%s' "$input" | bash ~/.claude/your-statusline.sh)
printf '%s\n%s' "$prayer" "$base"
```

## Cache

Lives in `~/.cache/muslim-statusline/`. Delete it to force a refresh (e.g. after traveling).
