"""Prints the SHAPE of the NCC API responses (field names, counts and types). It never prints the token,
names, phone numbers, emails, transcripts or summary text. Run it from GitHub: Actions > Refresh demo data > Run workflow > mode: explore.
Version 3: looks for a richer workitem record (agent, events, AI summary) than the slim history list.
"""
import base64
import datetime
import http.client
import json
import os
import statistics
import sys
import urllib.error
import urllib.parse
import urllib.request

BASE = os.environ.get("NCC_BASE_URL", "").strip().rstrip("/") or "https://mancity.thrio.io"
TOKEN = os.environ.get("NCC_TOKEN", "").strip()
UA = "Mozilla/5.0 (compatible; ncc-dashboard)"
PATH = "/analytics/api/types/workitems/history"


def api(path, params=None):
    url = BASE + path + ("?" + urllib.parse.urlencode(params) if params else "")
    req = urllib.request.Request(url, headers={"authorization": TOKEN, "accept": "application/json", "user-agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read().decode("utf-8")
            try:
                return r.status, json.loads(raw)
            except ValueError:
                return r.status, None
    except urllib.error.HTTPError as e:
        return e.code, None
    except Exception as e:
        return 0, str(type(e).__name__)


def objs_of(j):
    if isinstance(j, dict):
        return j.get("objects") or []
    return []


SEEN = set()


def keys_of(objs):
    k = set()
    for o in objs:
        if isinstance(o, dict):
            k |= set(o)
    SEEN.update(k)
    return k


STATS_PREFIXES = ["/statistics", "/stats", "/analytics", "/users", "/data", "/workflows", ""]
STATS_TAILS = ["/api/stats/users", "/api/stats/queues", "/api/stats/workitems", "/api/stats/campaigns", "/api/stats"]
WS_PATHS = ["/statistics/ws", "/statistics/websocket", "/statistics/stomp", "/stats/ws", "/ws", "/websocket", "/stomp", "/users/ws", "/socket"]


def names(j):
    if isinstance(j, list):
        first = sorted(j[0]) if j and isinstance(j[0], dict) else []
        return f"list[{len(j)}]" + (", item fields: " + ", ".join(first)[:500] if first else "")
    if isinstance(j, dict):
        return "object fields: " + ", ".join(sorted(j))[:500]
    return type(j).__name__


def drill(j):
    """Field NAMES and counts only, for the supervisor stats message shape."""
    st = j.get("stats") if isinstance(j, dict) else None
    if not isinstance(st, dict):
        return
    for part, items in st.items():
        if isinstance(items, dict) and items:
            first = next(iter(items.values()))
            print(f"     stats.{part}: {len(items)} items; item fields: " + (", ".join(sorted(first))[:600] if isinstance(first, dict) else type(first).__name__))
            if isinstance(first, dict) and isinstance(first.get("media"), dict) and first["media"]:
                m = first["media"]
                mf = next(iter(m.values()))
                print(f"       media types seen: {sorted(m)}")
                print("       media fields: " + (", ".join(sorted(mf))[:500] if isinstance(mf, dict) else ""))
        else:
            print(f"     stats.{part}: {tname(items) if 'tname' in globals() else type(items).__name__}")


def stats_probe():
    print("\n8. REAL-TIME STATISTICS REST ADDRESSES (only non-404 results are listed):")
    found, n404 = [], 0
    for pre in STATS_PREFIXES:
        for tail in STATS_TAILS:
            path = pre + tail
            code, j = api(path)
            if code == 404:
                n404 += 1
                continue
            print(f"   {code}  {path}")
            if code == 200 and j is not None:
                found.append((path, j))
    print(f"   ({n404} other addresses returned 404)")
    for path, j in found:
        print(f"   {path} -> {names(j)}")
        drill(j)
    host = BASE.split("://", 1)[1].split("/")[0]
    print("\n9. WEBSOCKET ADDRESS CHECK (101, 400, 401, 403 or 426 usually means something is listening; 404 means no):")
    for p in WS_PATHS:
        try:
            conn = http.client.HTTPSConnection(host, timeout=15) if BASE.startswith("https") else http.client.HTTPConnection(host, timeout=15)
            conn.request("GET", p, headers={"Upgrade": "websocket", "Connection": "Upgrade", "Sec-WebSocket-Version": "13",
                                            "Sec-WebSocket-Key": base64.b64encode(os.urandom(16)).decode(), "Authorization": TOKEN, "User-Agent": UA})
            r = conn.getresponse()
            print(f"   {r.status}  {p}")
            conn.close()
        except Exception as e:
            print(f"   error {type(e).__name__}  {p}")


def main():
    print("Base URL:", BASE)
    print("Token present:", bool(TOKEN), "| length:", len(TOKEN))
    if not TOKEN:
        print("ERROR: NCC_TOKEN is empty.")
        sys.exit(1)
    to_ms = int(datetime.datetime.now(datetime.timezone.utc).timestamp() * 1000)
    from_ms = to_ms - 3 * 86400000
    base = {"rows": 500, "start": 0, "q": "", "rangeType": "dateRange", "rangeFrom": from_ms, "rangeTo": to_ms}

    code, j = api(PATH, base)
    objs = objs_of(j)
    base_keys = keys_of(objs)
    print(f"\n1. HISTORY LIST (last 3 days): HTTP {code}, {len(objs)} workitems, {len(base_keys)} fields")
    print("   response keys:", sorted(j.keys()) if isinstance(j, dict) else None, "| next:", bool(j.get("next")) if isinstance(j, dict) else None)
    print("   fields:", ", ".join(sorted(base_keys)))

    dk = {}
    for o in objs:
        d = o.get("data")
        if isinstance(d, dict):
            for k in d:
                dk[k] = dk.get(k, 0) + 1
    with_data = sum(1 for o in objs if isinstance(o.get("data"), dict) and o["data"])
    print(f"\n1b. WORKFLOW VARIABLES inside the data field (names and counts only): {with_data} of {len(objs)} workitems have a non-empty data object")
    if dk:
        print("   " + ", ".join(f"{k}={v}" for k, v in sorted(dk.items(), key=lambda kv: (-kv[1], kv[0]))[:80]))
    else:
        print("   none")
    vals = [o.get("aiSummary") for o in objs]
    kinds = {}
    for v in vals:
        kinds[type(v).__name__] = kinds.get(type(v).__name__, 0) + 1
    texts = [v for v in vals if isinstance(v, str) and v.strip()]
    print(f"\n2. aiSummary FIELD: value types {kinds}; non-empty text on {len(texts)} of {len(objs)}")
    if texts:
        lens = [len(t) for t in texts]
        print(f"   text length min/median/max: {min(lens)}/{int(statistics.median(lens))}/{max(lens)}")
        print("   contains 'composite':", sum('composite' in t for t in texts), "| contains 'Overall Score':", sum('Overall Score' in t for t in texts), "| looks like HTML:", sum(t.lstrip().startswith('<') for t in texts))

    withsum = [o for o in objs if isinstance(o.get("aiSummary"), str) and o["aiSummary"].strip()]
    calls = [o for o in objs if str(o.get("type")) in ("InboundCall", "OutboundCall") and o.get("dispositionedAt")]
    samples = (withsum[:2] + calls[:3])[:4]
    print(f"\n3. FULLER RECORD BY ID: testing {len(samples)} workitems")
    for n, o in enumerate(samples, 1):
        wid = o.get("workitemId") or o.get("_id")
        c2, j2 = api(PATH, {**base, "rows": 5, "q": wid})
        o2 = objs_of(j2)
        extra = sorted(keys_of(o2) - base_keys)
        print(f"   history?q=<id> #{n}: HTTP {c2}, {len(o2)} rows, extra fields vs the list: {extra or 'none'}")
        for path in ("/data/api/types/workitem/" + str(wid), "/analytics/api/types/workitems/" + str(wid), "/users/api/workitems/" + str(wid)):
            c3, j3 = api(path)
            ex = sorted(set(j3) - base_keys) if isinstance(j3, dict) else None
            print(f"   {c3}  {path.replace(str(wid), '<id>')}" + (f" extra fields: {ex}" if ex else ""))
        if n >= 2:
            break

    c4, j4 = api(PATH, {**base, "rows": 20, "withRecordings": "true"})
    ex4 = sorted(keys_of(objs_of(j4)) - base_keys)
    print(f"\n4. withRecordings=true: HTTP {c4}, extra fields vs the list: {ex4 or 'none'}")

    c5, j5 = api("/data/api/types/workitems/find", {"rows": 5, "start": 0, "q": ""})
    o5 = objs_of(j5)
    print(f"\n5. /data/api/types/workitems/find: HTTP {c5}, {len(o5)} rows, extra fields vs the list: {sorted(keys_of(o5) - base_keys) or 'none'}")

    c6, j6 = api("/analytics/api/types/workitems/mycalls", {"limit": 5})
    o6 = objs_of(j6)
    print(f"\n6. mycalls (the token user's own calls): HTTP {c6}, {len(o6)} rows")
    if o6:
        print("   fields:", ", ".join(sorted(keys_of(o6))))

    print("\n7. LOOKUP LISTS (HTTP code and field names of the first row):")
    for path in ("/data/api/types/disposition", "/data/api/types/campaign", "/data/api/types/queue", "/data/api/types/user"):
        c7, j7 = api(path, {"rows": 3, "start": 0, "q": ""})
        o7 = objs_of(j7)
        print(f"   {c7}  {path}" + (f"  fields: {', '.join(sorted(o7[0]))[:300]}" if o7 and path != "/data/api/types/user" else ""))
    stats_probe()
    hits = sorted(k for k in SEEN if any(w in k.lower() for w in ("screen", "video", "recording", "transcri")))
    print("\n10. SCREEN, VIDEO, RECORDING AND TRANSCRIPT FIELDS seen anywhere above (field names only):", hits or "none")
    print("\nDone. Copy everything above into the chat.")


if __name__ == "__main__":
    main()
