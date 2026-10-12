# NCC Contact Center Dashboard (real data only)

A GitHub page that shows only numbers pulled from the NCC demo tenant (4258998).

## Pages
Overview (all channels, daily volume, busiest hours, dispositions), Channels, Agents, AI Interactions (the Gemini score card), Voice Handle Time, Call Outcomes, AI Summary, Data Sources.
The Data Sources page lists how each number is calculated and what is left out on purpose.

## How it works
1. A GitHub Action runs every 30 minutes (or when you click Run workflow).
2. It runs the files in `sql/` against BigQuery.
3. It saves counts and averages in `docs/data.json`.
4. The page in `docs/index.html` reads `data.json`.

Until the job succeeds, the page shows the snapshot built into `index.html` and says so in the top bar.

## The one secret
Name: `GCP_SA_KEY`
Where: Settings > Secrets and variables > Actions > New repository secret
What goes in it: the whole contents of a Google service account JSON key file with BigQuery Data Viewer on dataset `4258998` and BigQuery Job User on project `thrio-prod-4258998`.

## Known limits
- BigQuery only has a call after it is dispositioned. There are no live views.
- Wrap-up time includes the wait for the AI summary.
- Handle time ignores calls left undispositioned for over an hour.
- What NCC counts as a transfer is not yet confirmed.

## Channels and agents
Channels are grouped as Voice (InboundCall, OutboundCall), Dialer (PredictiveCall, ProgressiveCall, PredictiveSMS), SMS, Chat, Email and Survey.
Agent names are shortened from the agent username (derek.gray+superagent@nextiva.com becomes Derek Gray). The repo is public, so keep that in mind.
SMS workitems did not match REPORTS_WORKITEMS on callId in the data we pulled, so they are missing from agent and summary numbers.

## Refresh by hand (no key)
Open the Data Sources page, click Copy query, run it in BigQuery, copy the one result cell, paste it into the box, and click Show on dashboard. `sql/all_in_one.sql` is the same query. The pasted numbers stay in that browser.

## AI Interactions
Reads the AI score card (the QA prompt output in REPORTS_WORKITEMS, object, $.summary) with patterns: composite score, letter grade, pillar scores out of 4, sentiment, reason, disposition and coaching titles. `sql/ai_evals.sql` is for the scheduled job. `sql/ai_json.sql` is the same query wrapped for the by-hand paste. The patterns match the layouts we have seen, so a new layout may show blanks.

## Agent window
The agents query looks back 730 days (`DECLARE agent_days INT64 DEFAULT 730;` on its first line) and has no row limit, so it catches everyone who handled a workitem. Change 730 to look back further. Each agent also shows first and last seen dates and a search box. People who never handled a workitem are not in these tables.

## NCC API refresh (no Google key)
The workflow now runs `scripts/pull_api.py`. It logs in with one secret, `NCC_TOKEN` (a Security Token from the tenant page, Options Menu > Tenant > Security Tokens), reads workitem history one day at a time (the endpoint caps at 500 rows) and the tenant user list, and writes `docs/data.json`.
- The token goes in the `authorization` header with no "Bearer".
- Optional repository variable `NCC_BASE_URL` (default https://nextiva.thrio.io).
- Run **Actions > Refresh demo data > Run workflow** with mode `explore` first. It prints field names and counts only, so you can check the shapes before trusting the numbers.
- QA scores come from the AI summary on each workitem (ISDC or HEART). They are not the native NCC scorecard objects.
- The BigQuery scripts (`scripts/refresh.py`, `sql/`) stay in the repo for the by-hand paste on the Data Sources page.
