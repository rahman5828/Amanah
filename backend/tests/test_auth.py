"""Backend authentication tests — isolated in-memory SQLite."""

from datetime import datetime, timedelta, timezone

import jwt
import pytest
from app.core.config import settings
from app.core.security import create_access_token, hash_password, verify_password


def test_valid_registration(client):
    response = client.post(
        "/api/v1/auth/register",
        json={
            "full_name": "Alice Example",
            "email": "alice@example.com",
            "password": "password12",
        },
    )
    assert response.status_code == 201
    body = response.json()
    assert body["email"] == "alice@example.com"
    assert body["full_name"] == "Alice Example"
    assert "id" in body
    assert "password" not in body
    assert "password_hash" not in body


def test_duplicate_email(client, registered_user):
    response = client.post(
        "/api/v1/auth/register",
        json={
            "full_name": "Someone Else",
            "email": registered_user["email"],
            "password": "password12",
        },
    )
    assert response.status_code == 409
    assert "already exists" in response.json()["detail"].lower()


def test_successful_login(client, registered_user):
    response = client.post(
        "/api/v1/auth/login",
        json={
            "email": registered_user["email"],
            "password": registered_user["password"],
        },
    )
    assert response.status_code == 200
    body = response.json()
    assert "access_token" in body
    assert "refresh_token" in body
    assert body["token_type"] == "bearer"


def test_incorrect_password(client, registered_user):
    response = client.post(
        "/api/v1/auth/login",
        json={
            "email": registered_user["email"],
            "password": "wrong-password",
        },
    )
    assert response.status_code == 401
    detail = response.json()["detail"].lower()
    assert "invalid" in detail
    assert "not found" not in detail
    assert "no account" not in detail


def test_unknown_email_same_message(client):
    response = client.post(
        "/api/v1/auth/login",
        json={
            "email": "nobody@example.com",
            "password": "whatever12",
        },
    )
    assert response.status_code == 401
    assert response.json()["detail"] == "Invalid email or password."


def test_protected_profile_with_valid_token(client, registered_user):
    login = client.post(
        "/api/v1/auth/login",
        json={
            "email": registered_user["email"],
            "password": registered_user["password"],
        },
    )
    token = login.json()["access_token"]

    response = client.get(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["email"] == registered_user["email"]
    assert "password_hash" not in body


def test_missing_authorization_header(client):
    response = client.get("/api/v1/users/me")
    assert response.status_code == 401 or response.status_code == 403


def test_invalid_jwt(client):
    response = client.get(
        "/api/v1/users/me",
        headers={"Authorization": "Bearer not-a-real-jwt"},
    )
    assert response.status_code == 401


def test_expired_jwt(client, registered_user):
    expired_payload = {
        "sub": registered_user["id"],
        "exp": datetime.now(timezone.utc) - timedelta(minutes=5),
        "iat": datetime.now(timezone.utc) - timedelta(minutes=35),
        "type": "access",
    }
    token = jwt.encode(
        expired_payload,
        settings.JWT_SECRET_KEY,
        algorithm=settings.JWT_ALGORITHM,
    )

    response = client.get(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 401


def test_wrong_token_type_rejected(client, registered_user):
    payload = {
        "sub": registered_user["id"],
        "exp": datetime.now(timezone.utc) + timedelta(minutes=30),
        "iat": datetime.now(timezone.utc),
        "type": "refresh",
    }
    token = jwt.encode(
        payload,
        settings.JWT_SECRET_KEY,
        algorithm=settings.JWT_ALGORITHM,
    )
    response = client.get(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 401


def test_password_hashing_roundtrip():
    hashed = hash_password("securepass1")
    assert hashed != "securepass1"
    assert verify_password("securepass1", hashed) is True
    assert verify_password("wrong", hashed) is False


def test_create_access_token_claims():
    token = create_access_token("00000000-0000-0000-0000-000000000099")
    decoded = jwt.decode(
        token,
        settings.JWT_SECRET_KEY,
        algorithms=[settings.JWT_ALGORITHM],
    )
    assert decoded["sub"] == "00000000-0000-0000-0000-000000000099"
    assert decoded["type"] == "access"
    assert "exp" in decoded
    assert "iat" in decoded
