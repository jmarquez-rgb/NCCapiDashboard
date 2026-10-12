"""Prints the SHAPE of the NCC API responses (field names, counts and types). It never prints the token,
names, phone numbers, emails, transcripts or summary text. Run it from GitHub: Actions > Refresh demo data > Run workflow > mode: explore.
Version 3: looks for a richer workitem record (agent, events, AI summary) than the slim history list.
"""
import datetime
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


def keys_of(objs):
    k = set()
    for o in objs:
        if isinstance(o, dict):
            k |= set(o)
    return k


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
    print("\nDone. Copy everything above into the chat.")


if __name__ == "__main__":
    main()
