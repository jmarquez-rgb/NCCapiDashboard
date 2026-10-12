"""Runs the SQL files in /sql against BigQuery and writes docs/data.json.

Reads the Google service account key from the GCP_SA_KEY environment variable.
Only counts, averages and short labels are saved. No names, phone numbers or transcripts.
"""
import datetime
import decimal
import json
import os
import pathlib
import sys

from google.cloud import bigquery
from google.oauth2 import service_account

PROJECT = "thrio-prod-4258998"
ROOT = pathlib.Path(__file__).resolve().parent.parent

# These two must work. The page has nothing to show without them.
REQUIRED = ["kpis", "coverage_by_campaign"]
# These are nice to have. If one fails, the page keeps its snapshot values for that card.
OPTIONAL = [
    "channels",
    "agents",
    "wrap_by_summary",
    "stuck_calls",
    "termination_codes",
    "recent_calls",
    "daily",
    "hourly",
    "dispositions",
    "ai_evals",
]


def make_client():
    info = json.loads(os.environ["GCP_SA_KEY"])
    creds = service_account.Credentials.from_service_account_info(
        info, scopes=["https://www.googleapis.com/auth/bigquery"]
    )
    # Run jobs in the project the service account lives in. The tables are still read from thrio-prod-4258998.
    return bigquery.Client(project=info.get("project_id", PROJECT), credentials=creds)


def run(client, name):
    sql = (ROOT / "sql" / f"{name}.sql").read_text()
    return [dict(row) for row in client.query(sql).result()]


def plain(value):
    if isinstance(value, decimal.Decimal):
        return float(value)
    if isinstance(value, (datetime.date, datetime.datetime)):
        return value.isoformat()
    return str(value)


def main():
    client = make_client()
    out = {
        "updated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "window_days": 30,
        "kpis": run(client, "kpis")[0],
        "coverage": run(client, "coverage_by_campaign"),
    }
    errors = []
    for name in OPTIONAL:
        try:
            out[name] = run(client, name)
        except Exception as exc:  # keep going, report it on the Data Sources page
            out[name] = []
            errors.append(f"{name}: {str(exc)[:160]}")
    if errors:
        out["errors"] = errors
    path = ROOT / "docs" / "data.json"
    path.write_text(json.dumps(out, indent=2, default=plain))
    print("Wrote", path, "with", len(errors), "optional query errors")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # fail loudly so the red X shows in GitHub
        print("ERROR:", exc)
        sys.exit(1)
