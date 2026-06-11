# ☪️ muslim-statusline

Prayer times, hijri date, and rotating dhikr in your Claude Code statusline.

```
Opus · my-project@main · ☪️ 25 Dhū al-Ḥijjah 1447 · Benghazi
🕌 Asr 16:20 (in 50m) · 📿 سبحان الله وبحمده — SubhanAllahi wa bihamdihi
```

## What it does

- **Next prayer with countdown** — and for 20 minutes after the adhan: `🤲 Asr time — go pray`
- **Jumu'ah** — Friday's Dhuhr is labeled `Jumu'ah 🕌`
- **Ramadan mode** — automatic during the hijri month: iftar countdown through the day, suhoor deadline before Fajr
- **Hijri date** and your city
- **Dhikr** — rotates every 30 minutes through 10 adhkar (Arabic + transliteration)
- Works offline once cached: location is fetched weekly ([ip-api.com](http://ip-api.com)), prayer times once per day ([Aladhan API](https://aladhan.com/prayer-times-api)). No API keys. If the network is down, dhikr still shows.

## Install

```bash
git clone https://github.com/Sokanon/muslim-statusline.git
cd muslim-statusline
bash install.sh
```

Or tell Claude Code: *"Clone https://github.com/Sokanon/muslim-statusline and run its install.sh"*

Requirements: `jq`, `curl`, GNU date (on macOS: `brew install coreutils`).

## Configuration (optional)

Set these in the `env` block of `~/.claude/settings.json` (or export them):

| Variable | Default | Notes |
|---|---|---|
| `PRAYER_METHOD` | `3` (Muslim World League) | `5` = Egyptian (fits North Africa), `4` = Umm al-Qura, `2` = ISNA — [full list](https://aladhan.com/calculation-methods) |
| `PRAYER_LAT` / `PRAYER_LON` | auto via IP | set if IP geolocation is off (VPN, datacenter IP) |
| `PRAYER_CITY` | auto via IP | display name only |

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
