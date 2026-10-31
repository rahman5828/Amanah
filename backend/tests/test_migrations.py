"""Verify Alembic migrations work on a fresh empty database."""

from __future__ import annotations

import os
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect, text


BACKEND_ROOT = Path(__file__).resolve().parents[1]
ALEMBIC_INI = BACKEND_ROOT / "alembic.ini"
HEAD_REVISION = "b7e2c1a90f34"
INITIAL_REVISION = "93a3f4256bd7"


def _alembic_config(database_url: str) -> Config:
    """Build an Alembic Config that uses the given DATABASE_URL via settings."""
    # env.py reads DATABASE_URL from Pydantic settings (os.environ / .env).
    os.environ["DATABASE_URL"] = database_url
    os.environ.setdefault(
        "JWT_SECRET_KEY",
        "test-only-jwt-secret-key-not-for-production-use-32b",
    )
    os.environ.setdefault("APP_ENV", "test")

    cfg = Config(str(ALEMBIC_INI))
    # Ensure the app package is importable when env.py loads models/settings.
    cfg.set_main_option("sqlalchemy.url", database_url)
    return cfg


def test_fresh_database_runs_all_migrations(tmp_path):
    """Empty DB: upgrade head creates users then sessions (Neon-style path)."""
    db_path = tmp_path / "fresh.db"
    url = f"sqlite+pysqlite:///{db_path}"

    cfg = _alembic_config(url)
    # cwd must be backend so prepend_sys_path and migrations resolve.
    old_cwd = os.getcwd()
    try:
        os.chdir(BACKEND_ROOT)
        command.upgrade(cfg, "head")
    finally:
        os.chdir(old_cwd)

    engine = create_engine(url)
    try:
        insp = inspect(engine)
        tables = set(insp.get_table_names())
        assert "users" in tables
        assert "sessions" in tables
        assert "alembic_version" in tables

        user_cols = {c["name"] for c in insp.get_columns("users")}
        assert user_cols == {
            "id",
            "email",
            "full_name",
            "password_hash",
            "created_at",
        }

        session_cols = {c["name"] for c in insp.get_columns("sessions")}
        assert {
            "id",
            "user_id",
            "family_id",
            "refresh_token_hash",
            "device_label",
            "created_at",
            "expires_at",
            "last_used_at",
            "revoked_at",
            "replaced_by_id",
        } <= session_cols

        email_indexes = [
            ix
            for ix in insp.get_indexes("users")
            if "email" in (ix.get("column_names") or [])
        ]
        assert email_indexes, "expected unique index on users.email"
        assert any(ix.get("unique") for ix in email_indexes)

        fks = insp.get_foreign_keys("sessions")
        user_fks = [
            fk for fk in fks if fk.get("referred_table") == "users"
        ]
        assert user_fks, "sessions.user_id must FK to users.id"

        with engine.connect() as conn:
            version = conn.execute(
                text("SELECT version_num FROM alembic_version")
            ).scalar()
        assert version == HEAD_REVISION
    finally:
        engine.dispose()


def test_upgrade_head_is_noop_when_already_at_head(tmp_path):
    """Already-migrated DB stays at head; second upgrade does not error."""
    db_path = tmp_path / "already.db"
    url = f"sqlite+pysqlite:///{db_path}"
    cfg = _alembic_config(url)

    old_cwd = os.getcwd()
    try:
        os.chdir(BACKEND_ROOT)
        command.upgrade(cfg, "head")
        command.upgrade(cfg, "head")  # idempotent
        command.upgrade(cfg, "head")
    finally:
        os.chdir(old_cwd)

    engine = create_engine(url)
    try:
        with engine.connect() as conn:
            version = conn.execute(
                text("SELECT version_num FROM alembic_version")
            ).scalar()
        assert version == HEAD_REVISION
        # Tables still present after repeated upgrades
        insp = inspect(engine)
        assert "users" in insp.get_table_names()
        assert "sessions" in insp.get_table_names()
    finally:
        engine.dispose()


def test_downgrade_and_reupgrade_users_table(tmp_path):
    """Downgrade to base drops tables; re-upgrade recreates them."""
    db_path = tmp_path / "cycle.db"
    url = f"sqlite+pysqlite:///{db_path}"
    cfg = _alembic_config(url)

    old_cwd = os.getcwd()
    try:
        os.chdir(BACKEND_ROOT)
        command.upgrade(cfg, "head")
        command.downgrade(cfg, "base")
    finally:
        os.chdir(old_cwd)

    engine = create_engine(url)
    try:
        insp = inspect(engine)
        tables = set(insp.get_table_names())
        # alembic_version may remain empty or with no rows depending on dialect
        assert "users" not in tables
        assert "sessions" not in tables
    finally:
        engine.dispose()

    old_cwd = os.getcwd()
    try:
        os.chdir(BACKEND_ROOT)
        command.upgrade(cfg, "head")
    finally:
        os.chdir(old_cwd)

    engine = create_engine(url)
    try:
        insp = inspect(engine)
        assert "users" in insp.get_table_names()
        assert "sessions" in insp.get_table_names()
        with engine.connect() as conn:
            version = conn.execute(
                text("SELECT version_num FROM alembic_version")
            ).scalar()
        assert version == HEAD_REVISION
    finally:
        engine.dispose()


def test_initial_revision_is_not_empty():
    """Guard: initial migration must create users (regression for Neon)."""
    path = (
        BACKEND_ROOT
        / "migrations"
        / "versions"
        / "93a3f4256bd7_initial_user_table.py"
    )
    source = path.read_text()
    assert "op.create_table" in source
    assert '"users"' in source or "'users'" in source
    assert "email" in source and "password_hash" in source
    # Empty stub was only `pass` inside upgrade — reject that pattern.
    upgrade_body = source.split("def upgrade")[1].split("def downgrade")[0]
    assert "op.create_table" in upgrade_body
    assert INITIAL_REVISION in source
