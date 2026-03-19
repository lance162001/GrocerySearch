"""Admin dashboard — local-only DB explorer and scraper status."""

from __future__ import annotations

import os
import re
from pathlib import Path

from fastapi import APIRouter, HTTPException
from fastapi.responses import HTMLResponse
from pydantic import BaseModel as PydanticBase
from sqlalchemy import inspect, text

from models.base import engine, Base

admin_router = APIRouter(prefix="/admin", tags=["admin"])

_TEMPLATE_DIR = Path(__file__).resolve().parent.parent / "templates"
_DB_PATH = Path(__file__).resolve().parent.parent / "app.db"


def _read_scraper_status() -> dict | None:
    """Read scraper status from the database."""
    try:
        with engine.connect() as conn:
            row = conn.execute(
                text('SELECT * FROM scraper_status WHERE id = 1')
            ).mappings().first()
            if row is None:
                return None
            result = dict(row)
            # Convert datetime values to ISO strings for JSON
            for k, v in result.items():
                if hasattr(v, 'isoformat'):
                    result[k] = v.isoformat()
            result.pop('id', None)
            return result
    except Exception:
        return None


def _db_size_display() -> str:
    """Human-readable DB file size (SQLite) or 'PostgreSQL'."""
    db_url = str(engine.url)
    if "sqlite" in db_url:
        if _DB_PATH.exists():
            size = _DB_PATH.stat().st_size
            for unit in ("B", "KB", "MB", "GB"):
                if size < 1024:
                    return f"{size:.1f} {unit}"
                size /= 1024
            return f"{size:.1f} TB"
        return "unknown"
    return "PostgreSQL (remote)"


# ── Dashboard HTML ──────────────────────────────────────────────────
@admin_router.get("/", response_class=HTMLResponse)
async def dashboard_page():
    html = (_TEMPLATE_DIR / "admin.html").read_text()
    return HTMLResponse(html)


# ── Status JSON ─────────────────────────────────────────────────────
@admin_router.get("/status")
async def status():
    insp = inspect(engine)
    table_names = sorted(insp.get_table_names())
    table_counts: dict[str, int] = {}
    with engine.connect() as conn:
        for t in table_names:
            row = conn.execute(text(f'SELECT COUNT(*) FROM "{t}"')).scalar()
            table_counts[t] = row or 0

    db_url = str(engine.url)
    db_type = "SQLite" if "sqlite" in db_url else "PostgreSQL"

    return {
        "db": {
            "type": db_type,
            "size_display": _db_size_display(),
            "table_counts": table_counts,
        },
        "tables": table_names,
        "scraper": _read_scraper_status(),
    }


# ── Table browser ───────────────────────────────────────────────────
@admin_router.get("/table/{table_name}")
async def table_data(table_name: str, limit: int = 200):
    insp = inspect(engine)
    if table_name not in insp.get_table_names():
        raise HTTPException(404, f"Table '{table_name}' not found")

    columns = [c["name"] for c in insp.get_columns(table_name)]
    # Use 'id' for ordering when available (all models have it); fall back to
    # unordered for junction tables.  Avoids SQLite-only 'rowid'.
    order_clause = "ORDER BY id DESC" if "id" in columns else ""
    with engine.connect() as conn:
        rows = conn.execute(
            text(f'SELECT * FROM "{table_name}" {order_clause} LIMIT :lim'),
            {"lim": min(limit, 5000)},
        ).mappings().all()
    return {"columns": columns, "rows": [dict(r) for r in rows]}


# ── Read-only SQL console ──────────────────────────────────────────
class _SQLQuery(PydanticBase):
    sql: str


_FORBIDDEN = re.compile(
    r"\b(INSERT|UPDATE|DELETE|DROP|ALTER|CREATE|REPLACE|ATTACH|DETACH|PRAGMA\s+\w+\s*=)\b",
    re.IGNORECASE,
)


@admin_router.post("/sql")
async def run_sql(body: _SQLQuery):
    sql = body.sql.strip().rstrip(";")
    if not sql:
        raise HTTPException(400, "Empty query")
    if _FORBIDDEN.search(sql):
        raise HTTPException(
            403, "Only SELECT / read-only queries are allowed."
        )
    if not sql.upper().lstrip().startswith("SELECT") and not sql.upper().lstrip().startswith("WITH"):
        raise HTTPException(403, "Only SELECT queries are allowed.")

    try:
        with engine.connect() as conn:
            result = conn.execute(text(sql))
            columns = list(result.keys()) if result.returns_rows else []
            rows = [dict(r) for r in result.mappings().all()] if columns else []
    except Exception as exc:
        raise HTTPException(400, str(exc))

    return {"columns": columns, "rows": rows[:5000]}
