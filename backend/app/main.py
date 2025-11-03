"""FastAPI application entry-point for the SuperLuca backend.

This module exposes a FastAPI application and supporting database
utilities.  The original implementation crashed during application
startup when the SQLite ``user`` table was created with an older schema
that lacked the ``deleted_at`` column.  SQLModel's ``create_all`` helper
cannot add new columns to an existing table which meant that querying
``User`` triggered ``sqlite3.OperationalError: no such column``.  The
helpers below ensure the table schema is brought up to date before any
queries execute so that start-up succeeds even when the database was
initialised with a previous release of the application.
"""

from __future__ import annotations

import hashlib
import os
from contextlib import contextmanager
from datetime import datetime
from typing import Iterator, Optional

from fastapi import FastAPI
from sqlalchemy import text
from sqlmodel import Field, Session, SQLModel, create_engine, select

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./app.db")
engine = create_engine(
    DATABASE_URL,
    connect_args={"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {},
)


class User(SQLModel, table=True):
    """SQLModel representation of an application user."""

    id: Optional[int] = Field(default=None, primary_key=True)
    username: str = Field(index=True, unique=True)
    email: str
    password_hash: str
    recovery_key_hash: Optional[str] = None
    role: str = "admin"
    is_active: bool = True
    created_at: datetime = Field(default_factory=datetime.utcnow, nullable=False)
    deleted_at: Optional[datetime] = None


def _hash_secret(value: str) -> str:
    """Return a deterministic SHA-256 hash for the provided secret value."""

    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def ensure_user_table_schema() -> None:
    """Add missing columns to the ``user`` table when required.

    SQLite does not automatically add columns when SQLModel metadata is
    re-created.  This helper inspects the table definition and performs
    minimal ALTER TABLE migrations so that the application can operate on
    databases created by older versions of the codebase.
    """

    # ``create_all`` must run first to guarantee the table exists for brand
    # new deployments.
    SQLModel.metadata.create_all(engine)

    if not DATABASE_URL.startswith("sqlite"):
        # ``ALTER TABLE`` handling only applies to SQLite; other backends
        # rely on external migrations.
        return

    with engine.connect() as connection:
        table_exists = connection.execute(
            text("SELECT name FROM sqlite_master WHERE type='table' AND name='user';")
        ).scalar()
        if not table_exists:
            return

        existing_columns = {
            row[1] for row in connection.execute(text("PRAGMA table_info('user');"))
        }
        if "deleted_at" not in existing_columns:
            connection.execute(text('ALTER TABLE "user" ADD COLUMN deleted_at DATETIME'))
        connection.commit()


def init_db() -> None:
    """Initialise the application database."""

    ensure_user_table_schema()


@contextmanager
def get_session() -> Iterator[Session]:
    """Yield a managed SQLModel session bound to the global engine."""

    with Session(engine) as session:
        yield session


def seed_admin_user() -> None:
    """Create or update the default admin user.

    The function is idempotent and safe to call multiple times.  It
    ensures the ``deleted_at`` column exists before running any queries
    so that deployments using a legacy database schema continue to work.
    """

    init_db()

    username = os.getenv("ADMIN_USERNAME", "admin")
    email = os.getenv("ADMIN_EMAIL", "admin@example.com")
    password = os.getenv("ADMIN_PASSWORD", "ChangeM3!")
    role = os.getenv("ADMIN_ROLE", "admin")
    recovery_key = os.getenv("ADMIN_RECOVERY_KEY")

    password_hash = _hash_secret(password)
    recovery_key_hash = _hash_secret(recovery_key) if recovery_key else None

    with get_session() as session:
        admin = session.exec(select(User).where(User.username == username)).first()

        if admin is None:
            admin = User(
                username=username,
                email=email,
                password_hash=password_hash,
                recovery_key_hash=recovery_key_hash,
                role=role,
                is_active=True,
            )
            session.add(admin)
        else:
            updated = False
            if admin.email != email:
                admin.email = email
                updated = True
            if admin.role != role:
                admin.role = role
                updated = True
            if recovery_key_hash is not None and admin.recovery_key_hash != recovery_key_hash:
                admin.recovery_key_hash = recovery_key_hash
                updated = True
            if updated:
                session.add(admin)

        session.commit()


app = FastAPI(title="SuperLuca Backend")


@app.on_event("startup")
def on_startup() -> None:
    """FastAPI start-up hook used to prime the database."""

    seed_admin_user()


@app.get("/healthz")
def read_health() -> dict[str, str]:
    """Simple health endpoint used for readiness probes."""

    return {"status": "ok"}


__all__ = [
    "app",
    "engine",
    "get_session",
    "init_db",
    "seed_admin_user",
    "User",
]
