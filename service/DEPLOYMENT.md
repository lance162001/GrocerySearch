# GrocerySearch Backend Deployment (API + Scraper)

This runbook deploys the backend on a single Linux VM using Docker Compose.

## What This Deployment Includes

- FastAPI API service (`api`) on port `8000`
- PostgreSQL service (`db`) with persistent storage
- Shared static volume for scraped assets (`/app/static`)
- One-shot scraper job (`scraper`) for scheduled data refreshes
- One-shot logo refresh job (`logo_refresh`) for `/static/logos/*`

## 1) Prepare Host

Install Docker Engine and the Docker Compose plugin.

Example checks:

```bash
docker --version
docker compose version
```

Clone this repository to a stable location, for example:

```bash
sudo mkdir -p /opt/grocerysearch
sudo chown "$USER":"$USER" /opt/grocerysearch
git clone <your-repo-url> /opt/grocerysearch
cd /opt/grocerysearch/service
```

## 2) Create Production Environment File

Create `.env.prod` from the template and fill real values.

```bash
cd /opt/grocerysearch/service
cp .env.prod.example .env.prod
```

Minimum required values:

- `POSTGRES_PASSWORD`
- `ALLOWED_ORIGINS`
- `ALGOLIA_API_KEY`
- `SMTP_USERNAME`, `SMTP_PASSWORD`, `EMAIL_RECEIVER` (if you want summary emails)

## 3) Build and Start API + Database

```bash
cd /opt/grocerysearch/service
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build db api
```

Check health:

```bash
docker compose -f docker-compose.prod.yml --env-file .env.prod ps
curl -fsS http://127.0.0.1:${API_PORT:-8000}/
```

## 4) Run Jobs Manually (Smoke Test)

Run one scrape pass:

```bash
cd /opt/grocerysearch/service
./deploy/run_job.sh scrape
```

Run logo refresh:

```bash
cd /opt/grocerysearch/service
./deploy/run_job.sh logos
```

The job runner uses `flock` locks to prevent overlapping runs.

## 5) Enable systemd Timers

The provided unit files assume the repo is at `/opt/grocerysearch/service`.
If your path is different, edit `ExecStart` and `WorkingDirectory` first.

Install units:

```bash
sudo cp deploy/systemd/grocerysearch-scraper.service /etc/systemd/system/
sudo cp deploy/systemd/grocerysearch-scraper.timer /etc/systemd/system/
sudo cp deploy/systemd/grocerysearch-logos.service /etc/systemd/system/
sudo cp deploy/systemd/grocerysearch-logos.timer /etc/systemd/system/
sudo systemctl daemon-reload
```

Enable and start timers:

```bash
sudo systemctl enable --now grocerysearch-scraper.timer
sudo systemctl enable --now grocerysearch-logos.timer
```

Inspect next run times:

```bash
systemctl list-timers | grep grocerysearch
```

View job logs:

```bash
journalctl -u grocerysearch-scraper.service -n 200 --no-pager
journalctl -u grocerysearch-logos.service -n 200 --no-pager
```

## 6) Data Persistence

Compose named volumes preserve data across container recreation:

- `postgres_data` for PostgreSQL files
- `static_data` for `/app/static` (scraped product images + logos)

Back up both volumes regularly.

## 7) Updating Deployment

```bash
cd /opt/grocerysearch
# pull latest code
git pull
cd service
# rebuild and restart api/db
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build db api
```

## 8) Rollback (Quick)

If a new image fails, check logs and redeploy previous git commit:

```bash
cd /opt/grocerysearch
git checkout <known-good-commit>
cd service
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build db api
```

## Notes

- The API container command is now configurable with `UVICORN_WORKERS`.
- Scraper scheduling is intentionally externalized (systemd timer) to avoid duplicate in-process schedulers.
- If you later scale beyond one VM, migrate static assets to object storage and move to managed database/services.
