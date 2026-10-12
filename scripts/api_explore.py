"""Prints the SHAPE of the NCC API responses (field names, counts and types). It never prints the token,
names, phone numbers, emails, transcripts or summary text. Run it from GitHub: Actions > Refresh demo data > Run workflow > mode: explore.
"""
import datetime
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

BASE = os.environ.get("NCC_BASE_URL", "").strip().rstrip("/") or "https://nextiva.thrio.io"
TOKEN = os.environ.get("NCC_TOKEN", "").strip()
UA = "Mozilla/5.0 (compatible; ncc-dashboard)"


def api(path, params=None):
    url = BASE + path + ("?" + urllib.parse.urlencode(params) if params else "")
    req = urllib.request.Request(url, headers={"authorization": TOKEN, "accept": "application/json", "user-agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        return e.code, None
    except Exception as e:
        return 0, str(type(e).__name__)


def tname(v):
    return type(v).__name__ + (f"[{len(v)}]" if isinstance(v, (list, dict)) else "")


def shape(o, label):
    print(f"  {label}: {len(o)} keys")
    for k in sorted(o):
        print(f"    - {k}: {tname(o[k])}")


def main():
    print("Base URL:", BASE)
    print("Token present:", bool(TOKEN), "| length:", len(TOKEN))
    if not TOKEN:
        print("ERROR: NCC_TOKEN is empty.")
        sys.exit(1)
    now = datetime.datetime.now(datetime.timezone.utc)
    to_ms = int(now.timestamp() * 1000)
    from_ms = to_ms - 3 * 86400000
    first_with_rec = None
    sample = {}
    for wt in ["InboundCall", "OutboundCall", "PredictiveCall", "Chat", "InboundSMS", "Email"]:
        code, j = api("/analytics/api/v1/types/workitems/history", {"rows": 500, "start": 0, "q": "", "workitemType": wt, "rangeType": "dateRange", "rangeFrom": from_ms, "rangeTo": to_ms})
        if code != 200 or not isinstance(j, dict):
            print(f"\nHISTORY {wt} (last 3 days): HTTP {code}")
            continue
        objs = j.get("objects") or []
        print(f"\nHISTORY {wt} (last 3 days): HTTP {code}, {len(objs)} workitems, top-level keys of the response: {sorted(j.keys())}")
        if objs:
            sample[wt] = objs[0]
            for o in objs:
                if o.get("recordingId") and not first_with_rec:
                    first_with_rec = o
        if len(objs) >= 500:
            print("  NOTE: hit the 500 row cap")
    for wt, o in sample.items():
        print(f"\nWORKITEM SHAPE ({wt})")
        shape(o, "workitem")
        ev = o.get("timeEvents") or []
        print("  timeEvents types:", sorted({str(e.get("type")) for e in ev})[:40])
        s = o.get("summary")
        print("  summary present:", bool(s), "| length:", len(s) if isinstance(s, str) else 0, "| has 'composite':", isinstance(s, str) and "composite" in s, "| has 'Overall Score':", isinstance(s, str) and "Overall Score" in s)
        print("  has agentUsername:", "agentUsername" in o, "| campaignId:", "campaignId" in o, "| transcriptionMessages:", "transcriptionMessages" in o)
        hits = [k for k in o if any(w in k.lower() for w in ("score", "classif", "scorecard", "evaluation", "qa"))]
        print("  keys that look like scorecard results:", hits or "none")
    if first_with_rec:
        rid, created = first_with_rec["recordingId"], first_with_rec.get("createdAt") or to_ms
        code, j = api(f"/analytics/api/types/recording/{rid}", {"rangeType": "dateRange", "rangeFrom": created - 86400000, "rangeTo": created + 86400000})
        print(f"\nRECORDING OBJECT: HTTP {code}")
        if isinstance(j, dict):
            shape(j, "recording")
            print("  transcripts present:", bool(j.get("transcripts")), "| segments:", len(j.get("transcripts") or []))
            hits = [k for k in j if any(w in k.lower() for w in ("score", "classif", "scorecard", "evaluation"))]
            print("  keys that look like scorecard results:", hits or "none")
    code, j = api("/data/api/types/user", {"rows": 50, "start": 0, "q": ""})
    print(f"\nUSERS: HTTP {code}")
    if isinstance(j, dict):
        objs = j.get("objects") or []
        print("  first page:", len(objs), "| response keys:", sorted(j.keys()))
        if objs:
            shape(objs[0], "user")
    print("\nDone. Copy everything above into the chat.")


if __name__ == "__main__":
    main()
