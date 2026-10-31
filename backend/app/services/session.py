"""Session lifecycle: create, rotate, revoke, reuse detection."""

from __future__ import annotations

import hashlib
import secrets
import uuid
from datetime import datetime, timedelta, timezone

from sqlalchemy import select, update
from sqlalchemy.orm import Session as DbSession

from app.core.config import settings
from app.models.session import Session
from app.models.user import User


def hash_refresh_token(raw_token: str) -> str:
    """SHA-256 hex digest — suitable for high-entropy opaque tokens."""
    return hashlib.sha256(raw_token.encode("utf-8")).hexdigest()


def generate_refresh_token() -> str:
    return secrets.token_urlsafe(48)


def create_session(
    db: DbSession,
    user: User,
    *,
    device_label: str | None = None,
    family_id: uuid.UUID | None = None,
) -> tuple[Session, str]:
    """
    Create a new session row and return (session, raw_refresh_token).
    The raw token is returned once and never stored.
    """
    raw = generate_refresh_token()
    now = datetime.now(timezone.utc)
    session = Session(
        user_id=user.id,
        family_id=family_id or uuid.uuid4(),
        refresh_token_hash=hash_refresh_token(raw),
        device_label=device_label,
        expires_at=now + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS),
        last_used_at=now,
    )
    db.add(session)
    db.flush()
    return session, raw


def revoke_session(db: DbSession, session: Session) -> None:
    if session.revoked_at is None:
        session.revoked_at = datetime.now(timezone.utc)


def revoke_family(db: DbSession, family_id: uuid.UUID) -> int:
    """Revoke every session in a rotation family. Returns rows affected."""
    now = datetime.now(timezone.utc)
    result = db.execute(
        update(Session)
        .where(
            Session.family_id == family_id,
            Session.revoked_at.is_(None),
        )
        .values(revoked_at=now)
    )
    return result.rowcount or 0


def revoke_all_user_sessions(db: DbSession, user_id: uuid.UUID) -> int:
    now = datetime.now(timezone.utc)
    result = db.execute(
        update(Session)
        .where(
            Session.user_id == user_id,
            Session.revoked_at.is_(None),
        )
        .values(revoked_at=now)
    )
    return result.rowcount or 0


def get_session_by_refresh_token(
    db: DbSession,
    raw_token: str,
    *,
    for_update: bool = False,
) -> Session | None:
    token_hash = hash_refresh_token(raw_token)
    stmt = select(Session).where(Session.refresh_token_hash == token_hash)
    if for_update:
        stmt = stmt.with_for_update()
    return db.scalar(stmt)


def rotate_refresh_token(
    db: DbSession,
    raw_token: str,
    *,
    device_label: str | None = None,
) -> tuple[User, Session, str] | None:
    """
    Validate refresh token, rotate, return (user, new_session, new_raw_token).

    Reuse detection: if the token belongs to an already-revoked session
    (typically after rotation), revoke the entire family and return None.

    Returns None when the token is invalid, expired, or reuse was detected.
    """
    session = get_session_by_refresh_token(db, raw_token, for_update=True)

    if session is None:
        return None

    now = datetime.now(timezone.utc)

    if session.revoked_at is not None:
        revoke_family(db, session.family_id)
        db.commit()
        return None

    expires = session.expires_at
    if expires.tzinfo is None:
        expires = expires.replace(tzinfo=timezone.utc)
    if expires < now:
        revoke_session(db, session)
        db.commit()
        return None

    user = db.get(User, session.user_id)
    if user is None:
        revoke_session(db, session)
        db.commit()
        return None

    new_session, new_raw = create_session(
        db,
        user,
        device_label=device_label or session.device_label,
        family_id=session.family_id,
    )
    session.revoked_at = now
    session.replaced_by_id = new_session.id
    session.last_used_at = now
    new_session.last_used_at = now

    db.commit()
    db.refresh(new_session)
    return user, new_session, new_raw


def list_active_sessions(db: DbSession, user_id: uuid.UUID) -> list[Session]:
    now = datetime.now(timezone.utc)
    stmt = (
        select(Session)
        .where(
            Session.user_id == user_id,
            Session.revoked_at.is_(None),
            Session.expires_at > now,
        )
        .order_by(Session.created_at.desc())
    )
    return list(db.scalars(stmt).all())
