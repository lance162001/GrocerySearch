# GrocerySearch Frontend

This directory contains the active Flutter frontend for GrocerySearch.

## Structure

- `lib/main.dart`: app entrypoint and provider wiring
- `lib/state/`: shared frontend state
- `lib/services/`: backend API access
- `lib/models/`: frontend domain models
- `lib/widgets/`: shared presentation helpers

## Run Locally

1. Install packages:

```bash
flutter pub get
```

2. Start the backend service on `localhost:8000`.

3. Run the frontend:

```bash
flutter run -d chrome
```

Local backend mode is the default. To target the hosted backend instead:

```bash
flutter run -d chrome --dart-define=USE_LOCAL_BACKEND=false
```

For LAN device testing in debug mode, the app now prefers this order when
`USE_LOCAL_BACKEND=true`:

- `LOCAL_BACKEND_HOST`, if provided
- the current web page host, when running on Flutter web
- `localhost` as the final fallback

That means if you serve the web app on your machine's LAN IP, API calls will
use that same LAN IP instead of `localhost`.

Example web debug setup for other devices on your network:

```bash
cd ../service
uvicorn main:app --host 0.0.0.0 --port 8000

cd ../app
flutter run -d chrome --web-hostname 0.0.0.0 --web-port 3000
```

Then open `http://<your-lan-ip>:3000` from the test device.

For non-web debug targets, or if the backend runs on a different host than the
page you opened, pass the host explicitly:

```bash
flutter run -d <device> --dart-define=LOCAL_BACKEND_HOST=<your-lan-ip>
```

## Quality Checks

```bash
flutter analyze
flutter test
```

## Notes

- The Flutter package name is still `flutter_front_end` for import stability.
- User identity is cached through the platform-specific files in `lib/user_id_cache*.dart`.
- The bundle planner, product search, store selection, and checkout flows all use the shared `GroceryApi` service.
