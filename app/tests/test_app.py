import pytest

from webapp import create_app
from webapp.models import db


@pytest.fixture()
def client():
    app = create_app(
        {
            "TESTING": True,
            "SQLALCHEMY_DATABASE_URI": "sqlite:///:memory:",
            "SQLALCHEMY_ENGINE_OPTIONS": {},
            "LOAD_ENDPOINT_ENABLED": True,
        }
    )
    with app.app_context():
        yield app.test_client()
        db.session.remove()
        db.drop_all()


def test_health_is_shallow_and_ok(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.get_json() == {"status": "ok"}


def test_ready_checks_database(client):
    response = client.get("/health/ready")
    assert response.status_code == 200
    assert response.get_json()["database"] == "up"


def test_responses_carry_instance_headers(client):
    response = client.get("/health")
    assert response.headers["X-Served-By"]
    assert response.headers["X-Availability-Zone"]


def test_index_renders(client):
    response = client.get("/")
    assert response.status_code == 200
    assert b"Ops Board" in response.data


def test_task_crud_roundtrip(client):
    created = client.post("/api/tasks", json={"title": "Rotate keys", "priority": "high"})
    assert created.status_code == 201
    task = created.get_json()
    assert task["status"] == "todo"

    updated = client.put(f"/api/tasks/{task['id']}", json={"status": "done"})
    assert updated.get_json()["status"] == "done"
    assert updated.get_json()["title"] == "Rotate keys"

    listing = client.get("/api/tasks?status=done").get_json()
    assert [t["id"] for t in listing] == [task["id"]]

    assert client.delete(f"/api/tasks/{task['id']}").status_code == 204
    assert client.get(f"/api/tasks/{task['id']}").status_code == 404


@pytest.mark.parametrize(
    "payload",
    [
        {},
        {"title": "   "},
        {"title": "x" * 121},
        {"title": "ok", "status": "bogus"},
        {"title": "ok", "priority": "urgent"},
    ],
)
def test_create_validation(client, payload):
    response = client.post("/api/tasks", json=payload)
    assert response.status_code == 400
    assert "error" in response.get_json()


def test_non_json_body_rejected(client):
    response = client.post("/api/tasks", data="title=abc")
    assert response.status_code == 400


def test_stats(client):
    client.post("/api/tasks", json={"title": "a"})
    client.post("/api/tasks", json={"title": "b", "status": "done"})
    stats = client.get("/api/stats").get_json()
    assert stats["total"] == 2
    assert stats["counts"]["todo"] == 1
    assert stats["counts"]["done"] == 1
    assert stats["counts"]["in_progress"] == 0


def test_load_endpoint_runs_and_is_capped(client):
    response = client.post("/api/load?seconds=0.05")
    assert response.status_code == 200
    assert response.get_json()["rounds"] > 0


def test_load_endpoint_disabled_by_default():
    app = create_app({"TESTING": True, "SQLALCHEMY_DATABASE_URI": "sqlite:///:memory:", "SQLALCHEMY_ENGINE_OPTIONS": {}})
    response = app.test_client().post("/api/load?seconds=1")
    assert response.status_code == 404


def test_unknown_route_returns_json(client):
    response = client.get("/nope")
    assert response.status_code == 404
    assert response.get_json() == {"error": "not found"}
