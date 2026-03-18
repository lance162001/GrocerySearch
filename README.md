# GrocerySearch

A centralized API and frontend for grocery price analysis and comparison.

This repository combines a Python backend (scrapers, API, templates) with a
Flutter-based front end. It's a work-in-progress; current scrapers include
Whole Foods and Trader Joe's with more stores planned.

![Data Flow and UX Diagram](Data_Flow_UX_Diagram.jpeg?raw=true "Data Flow and UX Diagram")

## Quick Links

- Service: [service](service)
- Service deployment runbook: [service/DEPLOYMENT.md](service/DEPLOYMENT.md)
- Flutter front end: [app](app)

## Features

- Scrape product and pricing data from multiple grocery stores
- Expose a simple REST API for products, stores, and users under `service/api`
- Provide a Flutter UI for searching and visualizing results

## Quick Start

Service (Python)

1. Create a virtual environment and activate it:

```bash
python3 -m venv .venv
source .venv/bin/activate
```

2. Install dependencies and run the service (FastAPI/ASGI)

```bash
pip install -r service/requirements.txt
# Start with uvicorn (recommended): replace `service.main:app` with your app module and ASGI app name
uvicorn service.main:app --reload --host 127.0.0.1 --port 8000
```

Scraper

The scraper lives at `service/scraper.py`. It runs on a schedule by default and
will send a daily summary when it runs. To run a one-off immediate scrape or to
test behavior, use the debug flag which runs the scraping job immediately:

```bash
python service/scraper.py --debug
# or short form
python service/scraper.py -d
```

When run without the debug flag, the scraper runs in a loop and executes the
scheduled job (see `schedule` usage inside the script).

Flutter Front End

1. Change to the Flutter project and fetch packages:

```bash
cd app
flutter pub get
```

2. Run the app (example: Chrome):

```bash
flutter run -d chrome
```

3. To point the Flutter app at the remote backend instead of localhost, pass:

```bash
flutter run -d chrome --dart-define=USE_LOCAL_BACKEND=false
```

The Flutter package name remains `flutter_front_end`, but the active project
directory is `app/`.

## Development Notes

- Scrapers: `service/scraper.py` contains the scraping routines; extend it for
	additional stores and be mindful of site terms and rate limits.
- API endpoints live under `service/api` and use simple schemas in `service/schemas`.
- Data models are in `service/models` and can be extended for analytics or storage.
- Frontend state is now organized around a shared API service plus `provider`-backed app state under `app/lib/services` and `app/lib/state`.

## Contributing

- Fork and open a pull request. Keep changes focused and include tests where
	appropriate.
- If adding a new store scraper, include a short README explaining selectors
	and any special handling.

## License & Contact

See the `LICENSE` file at the repository root. For questions or collaboration,
open an issue or contact the maintainers via the project issue tracker.
