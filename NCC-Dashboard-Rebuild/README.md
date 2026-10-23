# NCC Analytics dashboard

A static dashboard for the NCC super demo tenant. It lives in `docs/` and is shown with GitHub Pages
(Settings > Pages > Branch `main`, folder `/docs`).

## What is in this repo
- `docs/index.html` is the whole dashboard. It carries its own queries and a built-in snapshot, so it works on its own.
- `docs/data.json` is made by the hourly job and replaces the built-in snapshot when it exists. Do not upload your own.
- `sql/` holds copies of the BigQuery questions. The dashboard has them built in behind its **Copy** buttons.
- `scripts/` holds the helpers the hourly job runs.
- `.github/workflows/refresh.yml` is the hourly job. It needs a secret `NCC_TOKEN` and a variable `NCC_BASE_URL`.

## Pages on the dashboard
Overview, Channels, Agents, QA / AI Score Cards, Channel Handle Time, Usage, Outcomes (by channel), AI Summary, Data Sources.

## How to tell which version is live
Look for the purple tag at the top of the page. The current one says **Build Oct 14 · v4**.
