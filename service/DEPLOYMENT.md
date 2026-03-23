# GrocerySearch Full-Stack Deployment (Frontend + API + Scraper)

This runbook deploys the Flutter web frontend and Python backend on a single Linux VM using Docker Compose.

## What This Deployment Includes

- Flutter web frontend service (`frontend`) on port `3000`
- FastAPI API service (`api`) on port `8000`
- PostgreSQL service (`db`) with persistent storage
- Continuous scraper service (`scraper`) in non-debug mode
- Shared static volume for scraped assets (`/app/static`)
- One-shot scraper job (`scraper_once`) for manual backfills
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
- `BASE_URL`
- `FRONTEND_USE_LOCAL_BACKEND=true`
- `FRONTEND_WEB_USE_SAME_ORIGIN_API=true`
- `ALGOLIA_API_KEY`
- `SMTP_USERNAME`, `SMTP_PASSWORD`, `EMAIL_RECEIVER` (if you want summary emails)

Set `ALLOWED_ORIGINS` to include the frontend origin, for example:

```env
ALLOWED_ORIGINS=http://your-server-ip:3000,https://yourdomain.com
```

Set `BASE_URL` to the public frontend origin used in newsletter links, for example:

```env
BASE_URL=https://yourdomain.com
```

## 3) Build and Start Frontend + API + Database

```bash
cd /opt/grocerysearch/service
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build db api frontend

# include scraper so the first scrape runs immediately and schedule loop stays active
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build scraper
```

Or as one command:

```bash
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build db api frontend scraper
```

The first frontend build can take several minutes because Flutter dependencies
and web artifacts are compiled inside the image.

Check health:

```bash
docker compose -f docker-compose.prod.yml --env-file .env.prod ps
curl -fsS http://127.0.0.1:${API_PORT:-8000}/
curl -I http://127.0.0.1:${FRONTEND_PORT:-3000}/
```

Open the app:

```text
http://<server-ip>:${FRONTEND_PORT}
```

Check scraper logs (first run can take a while):

```bash
docker compose -f docker-compose.prod.yml --env-file .env.prod logs -f scraper
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

This manual scrape path uses `scraper_once` with `--run-once` (non-debug).

## 5) Enable systemd Timers

The provided unit files assume the repo is at `/opt/grocerysearch/service`.
If your path is different, edit `ExecStart` and `WorkingDirectory` first.

The continuous `scraper` service already handles daily scheduling, so do not
enable the scraper timer in this mode (it would duplicate runs). Use only the
logo timer unless you intentionally switch off the continuous scraper service.

If you enabled the scraper timer in an earlier setup, disable it:

```bash
sudo systemctl disable --now grocerysearch-scraper.timer || true
```

Install units:

```bash
sudo cp deploy/systemd/grocerysearch-logos.service /etc/systemd/system/
sudo cp deploy/systemd/grocerysearch-logos.timer /etc/systemd/system/
sudo systemctl daemon-reload
```

Enable and start timers:

```bash
sudo systemctl enable --now grocerysearch-logos.timer
```

Inspect next run times:

```bash
systemctl list-timers | grep logos
```

View job logs:

```bash
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
# rebuild and restart frontend/api/scraper/db
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build db api frontend scraper
```

## 8) Rollback (Quick)

If a new image fails, check logs and redeploy previous git commit:

```bash
cd /opt/grocerysearch
git checkout <known-good-commit>
cd service
docker compose -f docker-compose.prod.yml --env-file .env.prod up -d --build db api frontend scraper
```

## Notes

- The API container command is now configurable with `UVICORN_WORKERS`.
- Frontend is built with Flutter `--dart-define` values from `.env.prod`.
- `FRONTEND_USE_LOCAL_BACKEND=true` keeps frontend API calls pointed at this deployment.
- `FRONTEND_WEB_USE_SAME_ORIGIN_API=true` (default) makes web clients call `/api/*` on the frontend origin, and nginx proxies those requests to the internal `api` container.
- Production scraper runs as a service in non-debug mode (`--run-on-start`), then continues normal schedule loop.
- If you later scale beyond one VM, migrate static assets to object storage and move to managed database/services.
