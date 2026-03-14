import os
from pathlib import Path
from sqlalchemy import create_engine, MetaData, event
from sqlalchemy.ext.declarative import declarative_base
from datetime import datetime
from sqlalchemy import Column, Integer, DateTime

Base = declarative_base()

# Use an absolute path for the sqlite DB so all processes open the same file
BASE_DIR = Path(__file__).resolve().parent.parent
default_db = BASE_DIR / "app.db"

DATABASE_URL = os.environ.get("DATABASE_URL")
if DATABASE_URL:
    db_url = DATABASE_URL
else:
    # sqlite absolute path (three slashes + absolute path -> sqlite:////abs/path)
    db_url = f"sqlite:///{default_db}"

# Ensure `check_same_thread=False` is present; append correctly whether query params exist or not
if "?" in db_url:
    engine_url = f"{db_url}&check_same_thread=False"
else:
    engine_url = f"{db_url}?check_same_thread=False"

engine = create_engine(engine_url, echo=False)

# Enable WAL journal mode and a generous busy timeout so that concurrent
# scraper threads (WF/TJ/WG) don't immediately raise "database is locked".
if db_url.startswith("sqlite"):
    @event.listens_for(engine, "connect")
    def _set_sqlite_pragmas(dbapi_conn, _record):
        cursor = dbapi_conn.cursor()
        cursor.execute("PRAGMA journal_mode=WAL")
        cursor.execute("PRAGMA busy_timeout=30000")
        cursor.close()

class BaseModel:
    id = Column(Integer, primary_key=True)