from fastapi import FastAPI
from fastapi.responses import JSONResponse
from sqlalchemy import text
from api import router
from api.products import _schedule_full_refresh
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
import os


app = FastAPI(
    docs_url=None if os.getenv("DISABLE_DOCS") else "/docs",
    redoc_url=None if os.getenv("DISABLE_DOCS") else "/redoc",
)

_default_origins = "http://localhost:3000,http://localhost:8000"
allowed_origins = [
    o.strip()
    for o in os.getenv("ALLOWED_ORIGINS", _default_origins).split(",")
    if o.strip()
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/health", include_in_schema=False)
async def health():
    """Liveness + readiness probe: verifies the DB is reachable."""
    from models.base import engine
    try:
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        return {"status": "ok"}
    except Exception as exc:
        return JSONResponse(
            status_code=503,
            content={"status": "degraded", "detail": str(exc)},
        )


# Mount static files (e.g., logos saved to service/static/logos)
static_dir = os.path.join(os.path.dirname(__file__), 'static')
os.makedirs(static_dir, exist_ok=True)
app.mount('/static', StaticFiles(directory=static_dir), name='static')

app.include_router(router)


@app.on_event("startup")
async def _warm_staple_cache():
    """On startup, refresh any per-store staple cache entries that are stale or missing."""
    _schedule_full_refresh()
