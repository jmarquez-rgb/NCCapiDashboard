"""Pulls workitem history and users from the NCC API and writes docs/data.json.

No Google key needed. It needs one secret, NCC_TOKEN (a Security Token from the tenant page).
Only counts, averages and short labels are saved. No names beyond agent display names, no phone numbers, no transcripts.

Documented in Confluence: "Pull a Call Recording and Transcript via API" and "How to Get an NCC API Token".
- The token goes in the authorization header with NO "Bearer " prefix.
- /analytics/api/v1/types/workitems/history caps at 500 rows and ignores paging, so we ask for one day at a time
  (and split a day into smaller windows when it hits 500).
"""
import datetime
import json
import os
import pathlib
import re
import statistics
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

BASE = os.environ.get("NCC_BASE_URL", "").strip().rstrip("/") or "https://mancity.thrio.io"
TOKEN = os.environ.get("NCC_TOKEN", "").strip()
DAYS = int(os.environ.get("WINDOW_DAYS", "30") or 30)
WORKERS = int(os.environ.get("WORKERS", "6") or 6)
MAX_MINUTES = float(os.environ.get("MAX_MINUTES", "20") or 20)  # stop fetching after this long and save what we have
ROOT = pathlib.Path(__file__).resolve().parent.parent
TZ = datetime.timezone(datetime.timedelta(hours=-7))  # Arizona, no daylight saving
UA = "Mozilla/5.0 (compatible; ncc-dashboard)"  # the WAF blocks the default Python user agent
TYPES = ["InboundCall", "OutboundCall", "PredictiveCall", "ProgressiveCall", "Chat", "InboundSMS",
         "OutboundSMS", "PredictiveSMS", "Email", "OutboundEmail", "Survey"]
GROUP = {"InboundCall": "voice", "OutboundCall": "voice", "PredictiveCall": "dialer", "ProgressiveCall": "dialer",
         "PredictiveSMS": "dialer", "Chat": "chat", "InboundSMS": "sms", "OutboundSMS": "sms", "Email": "email",
         "OutboundEmail": "email", "Survey": "survey"}
VOICE = ("InboundCall", "OutboundCall")
CAMPAIGNS = {
    "691f3f26edc70c6453096242": "Xbert Shop - Outbound", "6a8614bfdef3231972996ff1": "Xbert AI",
    "68e6aa86b190811f17f02bc5": "Xbert Bank - CSAT", "69eb8fe4d04e37610b862fe2": "Xbert Bank - CTI Outbound",
    "68e6e31b45e0eb17aeccba66": "Xbert Bank - DTMF", "68e6a723b190811f17f02bb6": "Xbert Bank - IVA",
    "691f6296568fd2419e8cf301": "Xbert Bank - Outbound", "6a2998ed32621d3782a41cbf": "Xbert Bank - Outbound Progressive",
    "68e5807eeda49a5413b993fb": "Xbert Care - CSAT", "68e5a67b5a2dc018eec1309d": "Xbert Care - DTMF",
    "68e58027eda49a5413b993f7": "Xbert Care - IVA", "691f62cbedc70c6453096687": "Xbert Care - Outbound",
    "699351d0ebe1f828ba7f33b0": "Xbert Intake - IVA", "68e7e9f5e685300e3a1672e2": "Xbert Shop - CSAT",
    "68e7ea52e685300e3a1672e5": "Xbert Shop - DTMF", "68fa3caf9373211d564404a0": "Xbert Shop - IVA",
    "6aaaadf638693d009e3ae4d3": "Xbert Unified - DTMF",
}


def api(path, params=None):
    url = BASE + path + ("?" + urllib.parse.urlencode(params) if params else "")
    req = urllib.request.Request(url, headers={"authorization": TOKEN, "accept": "application/json", "user-agent": UA})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=45) as r:
                return json.loads(r.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            if e.code in (429, 502, 503, 504) and attempt < 2:
                time.sleep(2 + attempt * 3)
                continue
            raise RuntimeError(f"HTTP {e.code} on {path}")
    raise RuntimeError("unreachable")


HISTORY_PATHS = [
    os.environ.get("NCC_HISTORY_PATH", "").strip(),
    "/analytics/api/types/workitems/history",
    "/analytics/api/v1/types/workitems/history",
    "/analytics/api/v1/types/workitem/history",
    "/analytics/api/types/workitem/history",
]
_working = []


def history(wtype, a, b):
    # The history endpoint ignores workitemType (it returns every type for the window), so we do not send it.
    params = {"rows": 500, "start": 0, "q": "",
              "rangeType": "dateRange", "rangeFrom": a, "rangeTo": b}
    paths = _working or [p for p in HISTORY_PATHS if p]
    last = None
    for path in paths:
        try:
            j = api(path, params)
        except RuntimeError as exc:
            last = exc
            if "HTTP 404" in str(exc):
                continue  # wrong address, try the next one
            raise
        if not _working:
            _working.append(path)
            print("History endpoint found:", path)
        return j.get("objects") or []
    raise RuntimeError(f"no history endpoint answered ({last}). Run the explorer to find the right path")


def window(wtype, a, b, depth=0):
    objs = history(wtype, a, b)
    if len(objs) >= 500 and b - a > 600000 and depth < 8:  # hit the cap, so split the window in two
        mid = (a + b) // 2
        return window(wtype, a, mid, depth + 1) + window(wtype, mid + 1, b, depth + 1)
    return objs


# ---------- reading one workitem ----------
def ev_sum(events, name):
    return sum(e.get("duration") or 0 for e in events if e.get("type") == name)


def norm(w, wtype):
    ev = w.get("timeEvents") or []
    ring = ev_sum(ev, "ringtime")
    term = ev_sum(ev, "userterminated")
    talk = max(0, term - ring) if term else 0
    hold = ev_sum(ev, "userhold")
    wrap = ev_sum(ev, "userdisposition")
    disp = next((e.get("displayName") for e in ev if e.get("type") == "userdisposition" and e.get("displayName")), None)
    created = w.get("createdAt") or 0
    summ = w.get("summary") or (w.get("aiSummary") if isinstance(w.get("aiSummary"), str) else None) or None
    cid = w.get("campaignId") or ""
    cname = w.get("campaignName")
    craw = w.get("campaign")
    if isinstance(craw, dict):
        cname = cname or craw.get("name")
        cid = cid or str(craw.get("_id") or craw.get("id") or "")
    elif isinstance(craw, str):
        if craw in CAMPAIGNS:
            cid = cid or craw
        else:
            cname = cname or craw
    return {
        "has_events": bool(ev), "type": w.get("type") or w.get("workitemType") or "Unknown", "id": str(w.get("_id") or w.get("workitemId") or w.get("callId") or ""),
        "created": created, "talk": talk, "hold": hold, "wrap": wrap,
        "abandoned": any(str(e.get("type", "")).startswith("abandon") for e in ev),
        "transferred": any("transfer" in str(e.get("type", "")) for e in ev),
        "disp": disp, "summary": summ, "agent": w.get("agentUsername"),
        "campaign": cname or CAMPAIGNS.get(cid) or (cid[:8] if cid else "Unknown"),
    }


def first(rx, s, flags=0):
    m = re.search(rx, s or "", flags)
    return m.group(1).strip() if m else None


def parse_summary(s):
    """Same patterns as sql/ai_evals.sql, so the two sources agree."""
    if not s:
        return None
    long_ = "composite" in s
    short = "Overall Score" in s
    if not (long_ or short):
        return None
    comp = first(r">(\d{1,3})</div>\s*<div[^>]*>composite</div>", s)
    if comp is None:
        o = first(r"Overall Score:</b>\s*(\d+)", s)
        comp = round(int(o) / 16 * 100) if o else None
    else:
        comp = int(comp)
    names = re.findall(r'<span style="font-size:12px;font-weight:600">([^<]+)</span>', s) or re.findall(r"<b>([A-Za-z &]+): Score \d / 4</b>", s)
    scores = re.findall(r"Score: (\d)/4", s) or re.findall(r"<b>[A-Za-z &]+: Score (\d) / 4</b>", s)
    reason = first(r"<b>Reason:</b>\s*([^<]+)</p>", s)
    return {
        "template": "long" if long_ else "short", "composite": comp,
        "grade": first(r'font-size:42px;font-weight:700;color:#[0-9A-Fa-f]{6};line-height:1">([A-F])</span>', s),
        "benchmark_label": first(r"letter-spacing:0\.1em;color:rgba\(255,255,255,0\.7\);font-weight:600\">([^<]+)</span>", s),
        "pillar_names": names, "pillar_scores": [int(x) for x in scores],
        "customer_sentiment": first(r"(?:Patient|Customer|Caller)</span>\s*<span[^>]*>([^<]+)</span>", s) or first(r"<b>Customer:</b>\s*([^<]+)", s),
        "agent_sentiment": first(r">Agent</span>\s*<span[^>]*>([^<]+)</span>", s) or first(r"<b>Agent:</b>\s*([^<]+)", s),
        "reason": (reason or "")[:160] or None,
        "summary_disposition": first(r"<b>Disposition:</b>\s*([^<]+)</p>", s),
        "interaction_type": first(r"<b>Type:</b>\s*([^<]+)</p>", s),
        "coaching": re.findall(r'font-size:12px;font-weight:700;color:#[0-9A-Fa-f]{6};margin-bottom:3px">([^<]+)</div>', s),
    }


def summary_type(s):
    if not s:
        return "no summary"
    return "short ISDC" if "Overall Score" in s else "long composite" if "composite" in s else "other"


def agent_name(login):
    base = (login or "no.agent").split("@")[0].split("+")[0].replace(".", " ")
    return base.title()


def pct(a, p):
    if not a:
        return None
    a = sorted(a)
    return round(a[min(len(a) - 1, int(p / 100 * (len(a) - 1) + 0.5))] / 1000, 1)


def avg_ms(a):
    return round(sum(a) / len(a) / 1000, 1) if a else None


def build(items):
    out = {"source": "api", "updated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"), "window_days": DAYS}
    voice = [x for x in items if x["type"] in VOICE]
    conn = [x for x in voice if x["talk"] > 0]
    capped = [x for x in conn if x["wrap"] <= 3600000]
    hts = [x["talk"] + x["hold"] + x["wrap"] for x in conn]
    out["kpis"] = {
        "workitems": len(voice), "connected": len(conn), "abandoned_calls": sum(x["abandoned"] for x in voice),
        "transferred_calls": sum(x["transferred"] for x in voice),
        "talk_avg_sec": avg_ms([x["talk"] for x in conn]), "hold_avg_sec": avg_ms([x["hold"] for x in conn]),
        "acw_avg_sec_capped": avg_ms([x["wrap"] for x in capped]),
        "aht_mean_sec_capped": avg_ms([x["talk"] + x["hold"] + x["wrap"] for x in capped]),
        "aht_median_sec": pct(hts, 50), "stuck_over_1h": sum(1 for x in conn if x["wrap"] > 3600000)}
    cov = {}
    for x in conn:
        c = cov.setdefault(x["campaign"], {"campaignName": x["campaign"], "connected_calls": 0, "with_summary": 0, "short_isdc": 0, "long_composite": 0})
        c["connected_calls"] += 1
        c["with_summary"] += 1 if x["summary"] else 0
        c["short_isdc"] += 1 if x["summary"] and "Overall Score" in x["summary"] else 0
        c["long_composite"] += 1 if x["summary"] and "composite" in x["summary"] else 0
    out["coverage"] = sorted(cov.values(), key=lambda r: -r["connected_calls"])
    wb = {}
    for x in capped:
        wb.setdefault(summary_type(x["summary"]), []).append(x["wrap"])
    out["wrap_by_summary"] = sorted([{"summary_type": k, "calls": len(v), "wrapup_p25_sec": pct(v, 25), "wrapup_median_sec": pct(v, 50), "wrapup_p75_sec": pct(v, 75)} for k, v in wb.items()], key=lambda r: -r["calls"])
    out["stuck_calls"] = [{"campaignName": x["campaign"], "dispositionName": x["disp"] or "Unknown", "wrap_hours": round(x["wrap"] / 3600000, 1)} for x in sorted([x for x in conn if x["wrap"] > 3600000], key=lambda r: -r["wrap"])[:10]]
    out["termination_codes"] = []  # not in the history payload we have seen
    out["recent_calls"] = [{"workitem": x["id"][:8], "channelType": x["type"], "talk_sec": round(x["talk"] / 1000, 1), "wrapup_sec": round(x["wrap"] / 1000, 1),
                            "summary_type": {"no summary": "none", "short ISDC": "short", "long composite": "long"}.get(summary_type(x["summary"]), "other"),
                            "customer_sentiment": (parse_summary(x["summary"]) or {}).get("customer_sentiment")} for x in sorted(conn, key=lambda r: -r["created"])[:20]]
    ch = {}
    for x in items:
        c = ch.setdefault(x["type"], {"channelType": x["type"], "workitems": 0, "abandoned": 0, "transferred": 0, "connected": 0, "_h": [], "joined_workitems": 0, "with_summary": 0})
        c["workitems"] += 1
        c["abandoned"] += x["abandoned"]
        c["transferred"] += x["transferred"]
        c["connected"] += 1 if x["talk"] > 0 else 0
        if x["talk"] > 0 and x["wrap"] <= 3600000:
            c["_h"].append(x["talk"] + x["hold"] + x["wrap"])
        c["joined_workitems"] += 1
        c["with_summary"] += 1 if x["summary"] else 0
    out["channels"] = sorted([{**{k: v for k, v in c.items() if k != "_h"}, "handle_avg_sec_capped": avg_ms(c["_h"])} for c in ch.values()], key=lambda r: -r["workitems"])
    ag = {}
    for x in items:
        login = (x["agent"] or "no.agent").split("@")[0]
        a = ag.setdefault(login, {"agent_name": agent_name(x["agent"]), "agent_login": login, "workitems": 0, "calls": 0, "chats": 0, "sms": 0, "emails": 0, "connected_calls": 0, "transferred": 0, "_h": [], "with_summary": 0, "first_seen": None, "last_seen": None})
        a["workitems"] += 1
        g = GROUP.get(x["type"])
        a["calls"] += 1 if g in ("voice", "dialer") and "SMS" not in x["type"] else 0
        a["chats"] += 1 if g == "chat" else 0
        a["sms"] += 1 if "SMS" in x["type"] else 0
        a["emails"] += 1 if g == "email" else 0
        a["connected_calls"] += 1 if x["talk"] > 0 else 0
        a["transferred"] += x["transferred"]
        if x["talk"] > 0 and x["wrap"] <= 3600000:
            a["_h"].append(x["talk"] + x["hold"] + x["wrap"])
        a["with_summary"] += 1 if x["summary"] else 0
        d = datetime.datetime.fromtimestamp(x["created"] / 1000, TZ).date().isoformat() if x["created"] else None
        if d:
            a["first_seen"] = min(a["first_seen"] or d, d)
            a["last_seen"] = max(a["last_seen"] or d, d)
    out["agents"] = sorted([{**{k: v for k, v in a.items() if k != "_h"}, "handle_avg_sec_capped": avg_ms(a["_h"])} for a in ag.values()], key=lambda r: -r["workitems"])[:200]
    out["agent_days"] = DAYS
    days = {}
    for x in items:
        if not x["created"]:
            continue
        d = datetime.datetime.fromtimestamp(x["created"] / 1000, TZ).date().isoformat()
        r = days.setdefault(d, {"day": d, "workitems": 0, "voice": 0, "dialer": 0, "chat": 0, "sms": 0, "email": 0, "survey": 0, "abandoned": 0})
        r["workitems"] += 1
        r[GROUP.get(x["type"], "survey")] += 1
        r["abandoned"] += x["abandoned"]
    out["daily"] = [days[k] for k in sorted(days)]
    hr = {}
    for x in voice:
        if x["created"]:
            t = datetime.datetime.fromtimestamp(x["created"] / 1000, TZ)
            k = ((t.weekday() + 1) % 7 + 1, t.hour)  # 1 = Sunday, to match BigQuery
            hr[k] = hr.get(k, 0) + 1
    out["hourly"] = [{"dow": k[0], "hour": k[1], "workitems": v} for k, v in sorted(hr.items())]
    dp = {}
    for x in items:
        if x["disp"]:
            dp[x["disp"]] = dp.get(x["disp"], 0) + 1
    out["dispositions"] = [{"dispositionName": k, "workitems": v} for k, v in sorted(dp.items(), key=lambda kv: -kv[1])[:12]]
    ev = []
    for x in sorted(items, key=lambda r: -r["created"]):
        p = parse_summary(x["summary"])
        if p and len(ev) < 60:
            ev.append({"workitem": x["id"][:8], "campaignName": x["campaign"], "channelType": x["type"], "transferred_to_agent": x["transferred"],
                       "talk_sec": round(x["talk"] / 1000, 1) if x["talk"] else None,
                       "day": datetime.datetime.fromtimestamp(x["created"] / 1000, TZ).date().isoformat(), "created_ms": x["created"], **p})
    out["ai_evals"] = ev
    return out


def users():
    rows, start, total = [], 0, None
    while start < 5000:
        j = api("/data/api/types/user", {"rows": 50, "start": start, "q": ""})
        objs = j.get("objects") or []
        total = j.get("total", total)
        for u in objs:
            nm = u.get("name") or (str(u.get("firstName", "")) + " " + str(u.get("lastName", ""))).strip() or str(u.get("username") or "")
            login = str(u.get("username") or "").split("@")[0]
            rows.append({"name": nm, "login": login, "active": bool(u.get("enabled", True)) and not u.get("deletedAt")})
        start += 50
        if len(objs) < 50 or (total is not None and start >= total):
            break
    return rows


def say(*a):
    print(*a, flush=True)


def main():
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except Exception:
        pass
    if not TOKEN:
        say("ERROR: NCC_TOKEN is empty. Add it under Settings > Secrets and variables > Actions.")
        sys.exit(1)
    say(f"Base URL: {BASE} | days: {DAYS} | workers: {WORKERS} | time limit: {MAX_MINUTES} min")
    now = datetime.datetime.now(TZ)
    midnight = now.replace(hour=0, minute=0, second=0, microsecond=0)
    # 1. find the working history address with one small call (shows the speed of a single call)
    t0 = time.time()
    try:
        a0 = int(midnight.timestamp() * 1000)
        history("InboundCall", a0, a0 + 86400000 - 1)
    except Exception as exc:
        say("ERROR:", exc)
        sys.exit(1)
    say(f"One history call took {time.time() - t0:.1f}s")
    deadline = time.time() + MAX_MINUTES * 60
    tasks = []
    for d in range(DAYS):  # newest days first, so a time-limited run still has the recent days
        a = int((midnight - datetime.timedelta(days=d)).timestamp() * 1000)
        tasks.append((d, a, a + 86400000 - 1))
    errors, items, done, skipped = [], [], 0, 0
    keys_seen, types_seen, raw_count = {}, {}, 0

    def work(task):
        d, a, b = task
        if time.time() > deadline:
            return task, None, None, "skipped"
        try:
            raw = window("", a, b)
            return task, [norm(w, "") for w in raw], raw, None
        except Exception as exc:
            return task, None, None, str(exc)

    fatal = None
    with ThreadPoolExecutor(max_workers=WORKERS) as pool:
        futs = [pool.submit(work, t) for t in tasks]
        for f in as_completed(futs):
            (d, a, b), got, raw, err = f.result()
            done += 1
            if got:
                items.extend(got)
                for w in raw:
                    raw_count += 1
                    for k in w:
                        keys_seen[k] = keys_seen.get(k, 0) + 1
                    t = str(w.get("type"))
                    types_seen[t] = types_seen.get(t, 0) + 1
            if err == "skipped":
                skipped += 1
            elif err:
                errors.append(f"day -{d}: {err}")
                if "HTTP 401" in err or "HTTP 403" in err:
                    fatal = err
            if done % 5 == 0 or done == len(tasks):
                say(f"  {done}/{len(tasks)} days done, {len(items)} workitems so far, {len(errors)} errors, {skipped} skipped")
            if fatal:
                for g in futs:
                    g.cancel()
                break
    if fatal:
        say("ERROR:", fatal, "(the token may be wrong, expired, or lacks permission)")
        sys.exit(1)
    say(f"\nFIELD REPORT (names and counts only) from {raw_count} workitems:")
    say("  types:", dict(sorted(types_seen.items(), key=lambda kv: -kv[1])[:14]))
    say("  fields:", ", ".join(f"{k}={v}" for k, v in sorted(keys_seen.items(), key=lambda kv: (-kv[1], kv[0]))[:70]))
    seen, uniq = set(), []
    for x in items:  # the same workitem can come back twice at window edges
        if x["id"] and x["id"] in seen:
            continue
        seen.add(x["id"])
        uniq.append(x)
    has_events = any(x["has_events"] for x in uniq)
    has_agent = any(x["agent"] for x in uniq)
    has_summary = any(x["summary"] for x in uniq)
    has_disp = any(x["disp"] for x in uniq)
    say(f"\nAI SUMMARY REPORT: {sum(1 for x in uniq if x['summary'])} of {len(uniq)} workitems have summary text; "
        f"{sum(1 for x in uniq if x['summary'] and 'composite' in x['summary'])} long composite, "
        f"{sum(1 for x in uniq if x['summary'] and 'Overall Score' in x['summary'])} short ISDC")
    say(f"Record has: timeEvents={has_events} agent={has_agent} summary={has_summary} dispositionName={has_disp}")
    out = build(uniq)
    drop = set()
    if not has_events:   # no talk/hold/wrap, abandon or transfer data in the record
        drop |= {"kpis", "coverage", "wrap_by_summary", "stuck_calls", "recent_calls", "channels", "termination_codes"}
    if not has_agent:
        drop.add("agents")
    if not has_summary:
        drop.add("ai_evals")
    if not has_disp:
        drop.add("dispositions")
    for k in drop:  # leave these out so the dashboard keeps its earlier values instead of showing blanks
        out.pop(k, None)
    out["source"] = "api-partial" if drop else "api"
    if drop:
        out["notes"] = ["The history record from the API does not carry: " + ", ".join(sorted(drop)) + ". Those sections keep their earlier values."]
        say("Left out because the record does not have the data:", ", ".join(sorted(drop)))
    if skipped:
        out["partial"] = True
        errors.insert(0, f"Stopped after {MAX_MINUTES} minutes. {skipped} of {len(tasks)} days were skipped (the oldest days).")
    try:
        out["users"] = users()
    except Exception as exc:
        out["users"] = []
        errors.append(f"users: {exc}")
    if errors:
        out["errors"] = errors[:8]
    (ROOT / "docs" / "data.json").write_text(json.dumps(out, indent=2, default=str))
    say("Wrote docs/data.json:", len(uniq), "workitems,", len(out.get("agents", [])), "agents,", len(out.get("ai_evals", [])), "AI evaluations,", len(out.get("users", [])), "users,", len(errors), "errors")


if __name__ == "__main__":
    main()
