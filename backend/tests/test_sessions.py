"""Refresh token rotation and session management tests."""

from datetime import datetime, timedelta, timezone

from sqlalchemy import select

from app.models.session import Session
from app.services.session import hash_refresh_token


def _login(client, registered_user, device_label=None):
    payload = {
        "email": registered_user["email"],
        "password": registered_user["password"],
    }
    if device_label:
        payload["device_label"] = device_label
    response = client.post("/api/v1/auth/login", json=payload)
    assert response.status_code == 200, response.text
    return response.json()


def test_login_returns_refresh_token(client, registered_user):
    data = _login(client, registered_user)
    assert "access_token" in data
    assert "refresh_token" in data
    assert len(data["refresh_token"]) >= 20
    assert data["token_type"] == "bearer"


def test_successful_refresh(client, registered_user):
    tokens = _login(client, registered_user)
    response = client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": tokens["refresh_token"]},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["access_token"]
    assert body["refresh_token"]
    assert body["refresh_token"] != tokens["refresh_token"]


def test_refresh_rotation_invalidates_old_token(client, registered_user):
    tokens = _login(client, registered_user)
    old_refresh = tokens["refresh_token"]

    first = client.post("/api/v1/auth/refresh", json={"refresh_token": old_refresh})
    assert first.status_code == 200
    new_refresh = first.json()["refresh_token"]

    reuse = client.post("/api/v1/auth/refresh", json={"refresh_token": old_refresh})
    assert reuse.status_code == 401

    again = client.post("/api/v1/auth/refresh", json={"refresh_token": new_refresh})
    assert again.status_code == 200


def test_refresh_token_reuse_revokes_family(client, registered_user, db_session):
    tokens = _login(client, registered_user)
    old_refresh = tokens["refresh_token"]

    rotated = client.post("/api/v1/auth/refresh", json={"refresh_token": old_refresh})
    assert rotated.status_code == 200
    new_refresh = rotated.json()["refresh_token"]

    reuse = client.post("/api/v1/auth/refresh", json={"refresh_token": old_refresh})
    assert reuse.status_code == 401

    after = client.post("/api/v1/auth/refresh", json={"refresh_token": new_refresh})
    assert after.status_code == 401


def test_invalid_refresh_token(client):
    response = client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": "this-is-not-a-valid-refresh-token-value"},
    )
    assert response.status_code == 401


def test_expired_refresh_token(client, registered_user, db_session):
    tokens = _login(client, registered_user)
    raw = tokens["refresh_token"]
    token_hash = hash_refresh_token(raw)

    session = db_session.scalar(
        select(Session).where(Session.refresh_token_hash == token_hash)
    )
    assert session is not None
    session.expires_at = datetime.now(timezone.utc) - timedelta(hours=1)
    db_session.commit()

    response = client.post("/api/v1/auth/refresh", json={"refresh_token": raw})
    assert response.status_code == 401


def test_logout_revokes_session(client, registered_user):
    tokens = _login(client, registered_user)
    response = client.post(
        "/api/v1/auth/logout",
        json={"refresh_token": tokens["refresh_token"]},
    )
    assert response.status_code == 204

    refresh = client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": tokens["refresh_token"]},
    )
    assert refresh.status_code == 401


def test_logout_unknown_token_still_204(client):
    response = client.post(
        "/api/v1/auth/logout",
        json={"refresh_token": "unknown-refresh-token-value-xxxx"},
    )
    assert response.status_code == 204


def test_multiple_sessions_per_user(client, registered_user):
    a = _login(client, registered_user, device_label="phone")
    b = _login(client, registered_user, device_label="tablet")

    assert a["refresh_token"] != b["refresh_token"]

    ra = client.post("/api/v1/auth/refresh", json={"refresh_token": a["refresh_token"]})
    rb = client.post("/api/v1/auth/refresh", json={"refresh_token": b["refresh_token"]})
    assert ra.status_code == 200
    assert rb.status_code == 200


def test_list_and_delete_sessions(client, registered_user):
    tokens = _login(client, registered_user, device_label="device-a")
    _login(client, registered_user, device_label="device-b")

    listed = client.get(
        "/api/v1/auth/sessions",
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
    )
    assert listed.status_code == 200
    sessions = listed.json()
    assert len(sessions) >= 2

    target_id = sessions[0]["id"]
    deleted = client.delete(
        f"/api/v1/auth/sessions/{target_id}",
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
    )
    assert deleted.status_code == 204

    listed2 = client.get(
        "/api/v1/auth/sessions",
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
    )
    ids = {s["id"] for s in listed2.json()}
    assert target_id not in ids


def test_refresh_token_not_stored_raw(client, registered_user, db_session):
    tokens = _login(client, registered_user)
    raw = tokens["refresh_token"]
    rows = list(db_session.scalars(select(Session)).all())
    for row in rows:
        assert raw not in (row.refresh_token_hash or "")
        assert len(row.refresh_token_hash) == 64


def test_access_token_still_works_for_profile(client, registered_user):
    tokens = _login(client, registered_user)
    response = client.get(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {tokens['access_token']}"},
    )
    assert response.status_code == 200
    assert response.json()["email"] == registered_user["email"]
