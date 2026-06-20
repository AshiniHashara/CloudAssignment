import pytest
from app import app, users_db, SEED_USERS


@pytest.fixture
def client():
    app.config["TESTING"] = True
    # Reset the in-memory user store fresh per test so registrations don't leak.
    users_db.clear()
    for u in SEED_USERS:
        users_db[u["id"]] = dict(u)
    with app.test_client() as client:
        yield client


def test_health(client):
    res = client.get("/health")
    assert res.status_code == 200
    assert res.get_json()["status"] == "healthy"


def test_ready(client):
    res = client.get("/ready")
    assert res.status_code == 200


def test_register_success(client):
    res = client.post(
        "/auth/register",
        json={"email": "new@cloudmart.example", "password": "password123", "name": "New User"},
    )
    body = res.get_json()
    assert res.status_code == 201
    assert body["user"]["email"] == "new@cloudmart.example"
    assert "passwordHash" not in body["user"]
    assert "token" in body


def test_register_missing_fields(client):
    res = client.post("/auth/register", json={"email": "new@cloudmart.example"})
    assert res.status_code == 400


def test_register_short_password(client):
    res = client.post(
        "/auth/register",
        json={"email": "new@cloudmart.example", "password": "short", "name": "New User"},
    )
    assert res.status_code == 400


def test_register_duplicate_email(client):
    res = client.post(
        "/auth/register",
        json={"email": "alice@cloudmart.example", "password": "password123", "name": "Dup"},
    )
    assert res.status_code == 409


def test_login_success(client):
    res = client.post(
        "/auth/login", json={"email": "alice@cloudmart.example", "password": "password123"}
    )
    body = res.get_json()
    assert res.status_code == 200
    assert body["user"]["email"] == "alice@cloudmart.example"
    assert "token" in body


def test_login_wrong_password(client):
    res = client.post(
        "/auth/login", json={"email": "alice@cloudmart.example", "password": "wrongpass"}
    )
    assert res.status_code == 401


def test_login_unknown_email(client):
    res = client.post(
        "/auth/login", json={"email": "nobody@cloudmart.example", "password": "password123"}
    )
    assert res.status_code == 401


def test_verify_token(client):
    login_res = client.post(
        "/auth/login", json={"email": "alice@cloudmart.example", "password": "password123"}
    )
    token = login_res.get_json()["token"]
    res = client.get("/auth/verify", headers={"Authorization": f"Bearer {token}"})
    assert res.status_code == 200
    assert res.get_json()["valid"] is True


def test_verify_token_missing(client):
    res = client.get("/auth/verify")
    assert res.status_code == 401


def test_get_my_profile(client):
    login_res = client.post(
        "/auth/login", json={"email": "alice@cloudmart.example", "password": "password123"}
    )
    token = login_res.get_json()["token"]
    res = client.get("/users/me", headers={"Authorization": f"Bearer {token}"})
    assert res.status_code == 200
    assert res.get_json()["email"] == "alice@cloudmart.example"


def test_update_my_profile(client):
    login_res = client.post(
        "/auth/login", json={"email": "alice@cloudmart.example", "password": "password123"}
    )
    token = login_res.get_json()["token"]
    res = client.put(
        "/users/me",
        headers={"Authorization": f"Bearer {token}"},
        json={"name": "Alice Updated"},
    )
    assert res.status_code == 200
    assert res.get_json()["name"] == "Alice Updated"


def test_get_user_public_profile(client):
    res = client.get("/users/user-001")
    body = res.get_json()
    assert res.status_code == 200
    assert body["id"] == "user-001"
    assert "passwordHash" not in body


def test_get_user_not_found(client):
    res = client.get("/users/does-not-exist")
    assert res.status_code == 404
