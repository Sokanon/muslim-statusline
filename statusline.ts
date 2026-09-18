#!/usr/bin/env bun
// muslim-statusline: prayer times + dhikr stacked on a usage statusline, in one script.
//
// Line 1: next prayer + countdown (go-pray window, Jumu'ah, Ramadan iftar/suhoor) · hijri · dhikr
// Line 2: model | project@branch (+adds -dels)
// Line 3: ctx | cost | 5h limit | 7d limit | extra usage
//
// Part 1 (prayer/hijri/dhikr) is original to this project.
// Part 2 (ctx/cost/limits) is adapted from claude-code-statusline by Aleksander Dytko
//   (MIT) — https://github.com/aleksander-dytko/claude-code-statusline
//
// One native process, no shell forks. Claude Code hard-kills a render the moment
// the next update arrives; an MSYS bash caught mid-fork by that kill aborts and
// drops a bash.exe.stackdump in the project directory. Network refreshes run in a
// detached child (`--refresh <kind>`), so a render never waits on the network.
//
// APIs: ip-api.com (location, cached 7 days), api.aladhan.com (timings, cached
// daily), api.anthropic.com OAuth usage (cached STATUSLINE_CACHE_TTL seconds).
// Env: PRAYER_LAT / PRAYER_LON / PRAYER_CITY, PRAYER_METHOD (3 = MWL, 5 = Egyptian),
//      MS_NO_HIJRI=1, MS_LINE_ONLY=1, MS_NOW=HH:MM, MS_HIJRI_MONTH=9 (test overrides),
//      STATUSLINE_SHOW_{GIT,CONTEXT,SESSION,WEEKLY,EXTRA,SESSION_COST}, STATUSLINE_CACHE_TTL,
//      STATUSLINE_CACHE_DIR, STATUSLINE_CURRENCY_SYMBOL, CLAUDE_CODE_OAUTH_TOKEN.

import {
  closeSync, mkdirSync, openSync, readdirSync, readFileSync, renameSync, rmdirSync,
  statSync, unlinkSync, utimesSync, writeFileSync,
} from "node:fs";
import { basename, join } from "node:path";
import { homedir, tmpdir } from "node:os";
import { spawn, spawnSync } from "node:child_process";

const env = process.env;
const HOME = homedir();
const CACHE = join(env.XDG_CACHE_HOME || join(HOME, ".cache"), "muslim-statusline");
const METHOD = env.PRAYER_METHOD || "3";
const USAGE_DIR = env.STATUSLINE_CACHE_DIR || join(tmpdir(), "claude");
const USAGE_TTL = Number(env.STATUSLINE_CACHE_TTL || 60);
const CURRENCY = env.STATUSLINE_CURRENCY_SYMBOL ?? "$";
const show = (k: string) => (env[`STATUSLINE_SHOW_${k}`] || "true") === "true";

const now = new Date();
const NOW = Math.floor(now.getTime() / 1000);
const pad = (n: number) => String(n).padStart(2, "0");
const TODAY = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
const DMY = `${pad(now.getDate())}-${pad(now.getMonth() + 1)}-${now.getFullYear()}`;
const DOW = ((now.getDay() + 6) % 7) + 1;

const LOC = join(CACHE, "location.json");
const TIM = join(CACHE, `timings-${TODAY}-m${METHOD}.json`);
const TIM_STAMP = join(CACHE, "fetch-attempt");
const USAGE_CACHE = join(USAGE_DIR, "statusline-usage-cache.json");
const USAGE_STAMP = join(USAGE_DIR, "statusline-fetch-attempt");
const RATELIMIT_STAMP = join(USAGE_DIR, "statusline-ratelimited");
const USAGE_LOCK = join(USAGE_DIR, "statusline-fetch.lock");

const mtime = (p: string) => { try { return Math.floor(statSync(p).mtimeMs / 1000); } catch { return 0; } };
const readText = (p: string) => { try { return readFileSync(p, "utf8"); } catch { return ""; } };
const readJson = (p: string): any => { try { return JSON.parse(readText(p)); } catch { return null; } };
const touch = (p: string) => { try { utimesSync(p, now, now); } catch { closeSync(openSync(p, "w")); } };
const writeAtomic = (p: string, s: string) => { const t = `${p}.tmp.${process.pid}`; writeFileSync(t, s); renameSync(t, p); };
const rm = (p: string) => { try { unlinkSync(p); } catch {} };

function detach(kind: string) {
  const child = spawn(process.execPath, [import.meta.path, "--refresh", kind], {
    detached: true, stdio: "ignore", windowsHide: true,
  });
  child.unref();
}

async function fetchJson(url: string, ms: number, headers?: Record<string, string>): Promise<any> {
  const r = await fetch(url, { headers, signal: AbortSignal.timeout(ms) });
  return r.json();
}

function resolveLocation(): { lat: string; lon: string; city: string } {
  let lat = env.PRAYER_LAT || "", lon = env.PRAYER_LON || "", city = env.PRAYER_CITY || "";
  if (!lat || !lon) {
    const loc = readJson(LOC);
    if (loc) { lat = String(loc.lat ?? ""); lon = String(loc.lon ?? ""); city ||= String(loc.city ?? ""); }
  }
  return { lat, lon, city };
}

function oauthToken(): string {
  if (env.CLAUDE_CODE_OAUTH_TOKEN) return env.CLAUDE_CODE_OAUTH_TOKEN;
  if (process.platform === "darwin") {
    const r = spawnSync("security", ["find-generic-password", "-s", "Claude Code-credentials", "-w"], { encoding: "utf8", timeout: 2000 });
    try { const t = JSON.parse(r.stdout || "")?.claudeAiOauth?.accessToken; if (t) return t; } catch {}
  }
  const t = readJson(join(HOME, ".claude", ".credentials.json"))?.claudeAiOauth?.accessToken;
  if (t) return t;
  if (process.platform === "linux") {
    const r = spawnSync("secret-tool", ["lookup", "service", "Claude Code-credentials"], { encoding: "utf8", timeout: 2000 });
    try { const t2 = JSON.parse(r.stdout || "")?.claudeAiOauth?.accessToken; if (t2) return t2; } catch {}
  }
  return "";
}

async function refresh(kind: string) {
  mkdirSync(CACHE, { recursive: true });
  if (kind === "location") {
    const j = await fetchJson("http://ip-api.com/json?fields=status,city,lat,lon", 3000).catch(() => null);
    if (j?.status === "success") writeAtomic(LOC, JSON.stringify(j));
  } else if (kind === "timings") {
    const { lat, lon } = resolveLocation();
    if (!lat || !lon) return;
    const j = await fetchJson(`https://api.aladhan.com/v1/timings/${DMY}?latitude=${lat}&longitude=${lon}&method=${METHOD}`, 4000).catch(() => null);
    if (!j?.data?.timings?.Fajr) return;
    writeAtomic(TIM, JSON.stringify(j));
    for (const f of readdirSync(CACHE)) {
      if (f.startsWith("timings-") && f.endsWith(".json") && f !== basename(TIM)) rm(join(CACHE, f));
    }
  } else if (kind === "usage") {
    mkdirSync(USAGE_DIR, { recursive: true });
    // mkdir is atomic, so only one session fetches at a time; a lock older than
    // 30s belongs to a fetcher that died and is taken over.
    const lock = () => { try { mkdirSync(USAGE_LOCK); return true; } catch { return false; } };
    let got = lock();
    if (!got && NOW - mtime(USAGE_LOCK) > 30) { try { rmdirSync(USAGE_LOCK); } catch {} got = lock(); }
    if (!got) return;
    try {
      const token = oauthToken();
      if (!token) return;
      const j = await fetchJson("https://api.anthropic.com/api/oauth/usage", 8000, {
        Accept: "application/json",
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
        "anthropic-beta": "oauth-2025-04-20",
        "User-Agent": "claude-code-statusline/1.0.0",
      }).catch(() => null);
      if (j?.five_hour) {
        writeAtomic(USAGE_CACHE, JSON.stringify(j));
        rm(RATELIMIT_STAMP);
      } else if (j?.error?.type === "rate_limit_error") {
        const n = parseInt(readText(RATELIMIT_STAMP).trim(), 10) || 0;
        writeFileSync(RATELIMIT_STAMP, String(n + 1));
      }
    } finally {
      try { rmdirSync(USAGE_LOCK); } catch {}
    }
  }
}

if (process.argv[2] === "--refresh") {
  await refresh(process.argv[3] || "");
  process.exit(0);
}

// ── Part 1: prayer times, hijri, dhikr ──────────────────────────────────────

const c = {
  green1: "\x1b[38;2;120;200;140m", teal: "\x1b[38;2;100;190;200m", gold: "\x1b[38;2;230;190;110m",
  blue: "\x1b[38;2;0;153;255m", orange: "\x1b[38;2;255;176;85m", green: "\x1b[38;2;0;160;0m",
  cyan: "\x1b[38;2;46;149;153m", red: "\x1b[38;2;255;85;85m", yellow: "\x1b[38;2;230;200;0m",
  white: "\x1b[38;2;220;220;220m", dim: "\x1b[2m", reset: "\x1b[0m",
};
const sep1 = ` ${c.dim}·${c.reset} `;
const sep2 = ` ${c.dim}|${c.reset} `;

mkdirSync(CACHE, { recursive: true });
if (!env.PRAYER_LAT || !env.PRAYER_LON) {
  if (NOW - mtime(LOC) > 604800) detach("location");
}
const { lat, lon } = resolveLocation();

let tim = readJson(TIM);
if (tim && !tim?.data?.timings?.Fajr) { rm(TIM); tim = null; }
if (!tim && lat && lon && NOW - mtime(TIM_STAMP) >= 60) { touch(TIM_STAMP); detach("timings"); }

const adhkar = [
  "سبحان الله وبحمده — SubhanAllahi wa bihamdihi",
  "لا إله إلا الله — La ilaha illa Allah",
  "الحمد لله — Alhamdulillah",
  "الله أكبر — Allahu Akbar",
  "أستغفر الله — Astaghfirullah",
  "لا حول ولا قوة إلا بالله — La hawla wa la quwwata illa billah",
  "اللهم صل على محمد ﷺ — Salawat upon the Prophet ﷺ",
  "سبحان الله العظيم — SubhanAllahil-Adheem",
  "حسبنا الله ونعم الوكيل — Hasbunallahu wa ni'mal wakeel",
  "رب اغفر لي — Rabbi-ghfir li",
];
const dhikr = adhkar[Math.floor(NOW / 1800) % adhkar.length];

const toMin = (hm: string) => { const [h, m] = hm.slice(0, 5).split(":"); return Number(h) * 60 + Number(m); };
const nowMin = toMin(env.MS_NOW || `${pad(now.getHours())}:${pad(now.getMinutes())}`);

let prayerLine = "", hijri = "";
if (tim) {
  const h = tim.data.date?.hijri ?? {};
  const hijriMonth = String(env.MS_HIJRI_MONTH || h.month?.number || "");
  hijri = `${h.day ?? ""} ${h.month?.en ?? ""} ${h.year ?? ""}`;

  const t = tim.data.timings as Record<string, string>;
  const names = ["Fajr", "Dhuhr", "Asr", "Maghrib", "Isha"];
  let next = "", nextMin = 99999, nextT = "", prev = "", prevMin = -99999;
  for (const p of names) {
    const tt = String(t[p] ?? "").slice(0, 5);
    const m = toMin(tt);
    if (m > nowMin && m < nextMin) { next = p; nextMin = m; nextT = tt; }
    if (m <= nowMin && m > prevMin) { prev = p; prevMin = m; }
  }
  if (!next) { next = "Fajr"; nextT = String(t.Fajr ?? "").slice(0, 5); nextMin = toMin(nextT) + 1440; }

  const diff = nextMin - nowMin;
  const cd = diff >= 60 ? `in ${Math.floor(diff / 60)}h ${diff % 60}m` : `in ${diff}m`;
  const label = DOW === 5 && next === "Dhuhr" ? "Jumu'ah 🕌" : next;

  if (prev && nowMin - prevMin <= 20) {
    prayerLine = `${c.gold}🤲 ${prev} time — go pray${c.reset}`;
  } else if (hijriMonth === "9" && next === "Maghrib") {
    prayerLine = `${c.gold}🌙 iftar ${cd} (${nextT})${c.reset}`;
  } else if (hijriMonth === "9" && (next === "Fajr" || prev === "")) {
    prayerLine = `${c.gold}🌙 suhoor ends at Fajr ${nextT} (${cd})${c.reset}`;
  } else {
    prayerLine = `${c.green1}🕌 ${label} ${nextT}${c.reset} ${c.dim}(${cd})${c.reset}`;
  }
}

const parts1: string[] = [];
if (prayerLine) parts1.push(prayerLine);
if (hijri && !env.MS_NO_HIJRI) parts1.push(`${c.gold}☪️ ${hijri}${c.reset}`);
parts1.push(`${c.teal}📿 ${dhikr}${c.reset}`);
const msLine = parts1.join(sep1);

if (env.MS_LINE_ONLY) {
  await Bun.write(Bun.stdout, msLine);
  process.exit(0);
}

// ── Part 2: model | git, then ctx | cost | limits ───────────────────────────

let input: any = {};
try { input = JSON.parse(await Bun.stdin.text()); } catch {}

const modelName = input.model?.display_name || "Claude";
const cwd: string = input.cwd || "";
const size = Number(input.context_window?.context_window_size) || 200000;
const usage = input.context_window?.current_usage ?? {};
const current = (Number(usage.input_tokens) || 0) + (Number(usage.cache_creation_input_tokens) || 0) + (Number(usage.cache_read_input_tokens) || 0);
const pctStdin = input.context_window?.used_percentage;
const pctUsed = pctStdin != null && pctStdin !== "" ? Math.round(Number(pctStdin)) || 0 : Math.floor(size > 0 ? current * 100 / size : 0);
const sessionCost = Number(input.cost?.total_cost_usd) || 0;
const wtName: string = input.worktree?.name || "";

const fmtTokens = (n: number) => n >= 1_000_000 ? `${(n / 1_000_000).toFixed(1)}m` : n >= 1000 ? `${Math.round(n / 1000)}k` : String(n);
const planColor = (p: number) => p >= 90 ? c.red : p >= 70 ? c.yellow : c.green;
const contextColor = (p: number) => p >= 75 ? c.red : p >= 50 ? c.yellow : c.green;
const extraColor = (p: number) => p >= 80 ? c.red : p >= 50 ? c.yellow : c.green;

const MONTHS = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
function fmtReset(iso: string, style: "time" | "datetime" | "date"): string {
  if (!iso || iso === "null") return "";
  const d = new Date(iso);
  if (isNaN(d.getTime())) return "";
  const hh = d.getHours();
  const time = `${hh % 12 || 12}:${pad(d.getMinutes())}${hh >= 12 ? "pm" : "am"}`;
  const date = `${MONTHS[d.getMonth()]} ${d.getDate()}`;
  return style === "time" ? time : style === "datetime" ? `${date}, ${time}` : date;
}
function fmtCountdown(iso: string): string {
  if (!iso || iso === "null") return "";
  const epoch = Date.parse(iso) / 1000;
  if (isNaN(epoch)) return "";
  const diff = Math.floor(epoch - NOW);
  if (diff <= 0) return "soon";
  const hours = Math.floor(diff / 3600), mins = Math.floor((diff % 3600) / 60);
  if (hours >= 24) return `resets in ${Math.floor(hours / 24)}d`;
  if (hours >= 1) return `resets in ${hours}h ${mins}min`;
  return `resets in ${mins}min`;
}

mkdirSync(USAGE_DIR, { recursive: true });
const usageData = readJson(USAGE_CACHE);
const haveUsage = !!usageData?.five_hour;

let rateLimited = false;
const rlRaw = readText(RATELIMIT_STAMP).trim();
if (rlRaw !== "" || mtime(RATELIMIT_STAMP)) {
  const n = Math.max(1, parseInt(rlRaw, 10) || 1);
  const backoff = Math.min(300, 30 * 2 ** (n - 1));
  rateLimited = NOW - mtime(RATELIMIT_STAMP) < backoff;
}
if (!rateLimited && NOW - mtime(USAGE_STAMP) >= USAGE_TTL) { touch(USAGE_STAMP); detach("usage"); }

let out1 = `${c.blue}${modelName}${c.reset}`;
if (show("GIT") && cwd) {
  const displayDir = cwd.replace(/\\/g, "/").replace(/\/$/, "").split("/").pop() || "";
  const git = (args: string[]) => {
    const r = spawnSync("git", ["-C", cwd, ...args], { encoding: "utf8", timeout: 2000, windowsHide: true });
    return r.status === 0 ? r.stdout : "";
  };
  const [branch = "", gitDir = ""] = git(["rev-parse", "--abbrev-ref", "HEAD", "--git-dir"]).split(/\r?\n/);
  out1 += `${sep2}${c.cyan}${displayDir}${c.reset}`;
  if (branch) {
    if (wtName) out1 += `${c.dim}[wt:${wtName}]${c.reset}`;
    else if (gitDir.includes("/worktrees/")) out1 += `${c.dim}[wt]${c.reset}`;
    out1 += `${c.dim}@${c.reset}${c.green}${branch}${c.reset}`;
    let adds = 0, dels = 0;
    for (const line of git(["diff", "HEAD", "--numstat"]).split("\n")) {
      const [a, d] = line.split("\t");
      adds += parseInt(a, 10) || 0; dels += parseInt(d, 10) || 0;
    }
    if (adds + dels > 0) out1 += ` ${c.dim}(${c.reset}${c.green}+${adds}${c.reset} ${c.red}-${dels}${c.reset}${c.dim})${c.reset}`;
  }
}

const cost: string[] = [];
if (show("CONTEXT")) cost.push(`${c.white}ctx${c.reset} ${c.orange}${fmtTokens(current)}/${fmtTokens(size)}${c.reset} ${c.dim}(${c.reset}${contextColor(pctUsed)}${pctUsed}%${c.reset}${c.dim})${c.reset}`);
if (show("SESSION_COST")) cost.push(`${c.white}cost ${CURRENCY}${sessionCost.toFixed(2)}${c.reset}`);

const limits: string[] = [];
if (haveUsage) {
  const fivePct = Math.round(Number(usageData.five_hour?.utilization) || 0);
  const sevenPct = Math.round(Number(usageData.seven_day?.utilization) || 0);
  const fiveReset = String(usageData.five_hour?.resets_at ?? "");
  const sevenReset = String(usageData.seven_day?.resets_at ?? "");
  const extra = usageData.extra_usage ?? {};
  const fiveOnExtra = fivePct >= 100, sevenOnExtra = sevenPct >= 100;

  if (show("SESSION")) {
    let seg = `${c.white}${fiveOnExtra ? "⚡ 5h" : "5h"}${c.reset} ${planColor(fivePct)}${fivePct}%${c.reset}`;
    const tail = fiveOnExtra ? fmtCountdown(fiveReset) : fmtReset(fiveReset, "time");
    if (tail) seg += ` ${c.dim}${fiveOnExtra ? "" : "@"}${tail}${c.reset}`;
    limits.push(seg);
  }
  if (show("WEEKLY")) {
    let seg = `${c.white}${sevenOnExtra ? "⚡ 7d" : "7d"}${c.reset} ${planColor(sevenPct)}${sevenPct}%${c.reset}`;
    const tail = sevenOnExtra ? fmtCountdown(sevenReset) : fmtReset(sevenReset, "datetime");
    if (tail) seg += ` ${c.dim}${sevenOnExtra ? "" : "@"}${tail}${c.reset}`;
    limits.push(seg);
  }
  if (show("EXTRA") && extra.is_enabled === true) {
    const used = ((Number(extra.used_credits) || 0) / 100).toFixed(2);
    const limit = ((Number(extra.monthly_limit) || 0) / 100).toFixed(2);
    const pct = Math.round(Number(extra.utilization) || 0);
    const label = fiveOnExtra || sevenOnExtra ? "extra ⚡" : "extra";
    limits.push(`${c.white}${label}${c.reset} ${extraColor(pct)}${CURRENCY}${used}/${CURRENCY}${limit}${c.reset}`);
  }
}
if (!limits.length && rateLimited && (show("SESSION") || show("WEEKLY") || show("EXTRA"))) {
  limits.push(`${c.dim}limits unavailable (rate limited)${c.reset}`);
}

const line3 = [...cost, ...limits].join(sep2);
const usageOut = line3 ? `${out1}\n${line3}` : out1;
await Bun.write(Bun.stdout, `${msLine}\n${usageOut}`);
