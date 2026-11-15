import hashlib
import time

from flask import Blueprint, current_app, jsonify, render_template, request
from sqlalchemy import text

from .instance import instance_info
from .models import PRIORITIES, STATUSES, Task, db

bp = Blueprint("main", __name__)


def _error(message: str, code: int = 400):
    return jsonify({"error": message}), code


def _validate(payload: dict, partial: bool = False):
    """Return (clean, error). With partial=True only supplied fields are checked."""
    clean = {}
    if "title" in payload or not partial:
        title = str(payload.get("title", "")).strip()
        if not 1 <= len(title) <= 120:
            return None, "title is required (1-120 characters)"
        clean["title"] = title
    if "description" in payload:
        description = str(payload["description"])
        if len(description) > 2000:
            return None, "description is limited to 2000 characters"
        clean["description"] = description
    if "status" in payload:
        if payload["status"] not in STATUSES:
            return None, f"status must be one of {', '.join(STATUSES)}"
        clean["status"] = payload["status"]
    if "priority" in payload:
        if payload["priority"] not in PRIORITIES:
            return None, f"priority must be one of {', '.join(PRIORITIES)}"
        clean["priority"] = payload["priority"]
    return clean, None


# ---------------------------------------------------------------- pages


@bp.get("/")
def index():
    return render_template("index.html", info=instance_info(), version=current_app.config["APP_VERSION"])


# ------------------------------------------------------------ health


@bp.get("/health")
def health():
    """Shallow liveness check used by the ALB target group and Route 53.

    It deliberately does not touch the database: during an RDS Multi-AZ failover
    (60-120 s) a deep check would mark every instance unhealthy and the ALB would
    have nothing to route to. Use /health/ready for the dependency check.
    """
    return jsonify(status="ok")


@bp.get("/health/ready")
def ready():
    try:
        db.session.execute(text("SELECT 1"))
    except Exception as exc:  # noqa: BLE001
        current_app.logger.warning("readiness check failed: %s", exc)
        return jsonify(status="degraded", database="down"), 503
    return jsonify(status="ok", database="up")


@bp.get("/api/info")
def info():
    return jsonify(**instance_info(), version=current_app.config["APP_VERSION"])


# ------------------------------------------------------------ tasks API


@bp.get("/api/tasks")
def list_tasks():
    query = Task.query
    status = request.args.get("status")
    if status:
        if status not in STATUSES:
            return _error(f"status must be one of {', '.join(STATUSES)}")
        query = query.filter_by(status=status)
    tasks = query.order_by(Task.id.desc()).limit(200).all()
    return jsonify([task.to_dict() for task in tasks])


@bp.post("/api/tasks")
def create_task():
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return _error("JSON body required")
    clean, error = _validate(payload)
    if error:
        return _error(error)
    task = Task(**clean)
    db.session.add(task)
    db.session.commit()
    return jsonify(task.to_dict()), 201


@bp.get("/api/tasks/<int:task_id>")
def get_task(task_id: int):
    return jsonify(db.get_or_404(Task, task_id).to_dict())


@bp.put("/api/tasks/<int:task_id>")
def update_task(task_id: int):
    task = db.get_or_404(Task, task_id)
    payload = request.get_json(silent=True)
    if not isinstance(payload, dict):
        return _error("JSON body required")
    clean, error = _validate(payload, partial=True)
    if error:
        return _error(error)
    for key, value in clean.items():
        setattr(task, key, value)
    db.session.commit()
    return jsonify(task.to_dict())


@bp.delete("/api/tasks/<int:task_id>")
def delete_task(task_id: int):
    task = db.get_or_404(Task, task_id)
    db.session.delete(task)
    db.session.commit()
    return "", 204


@bp.get("/api/stats")
def stats():
    rows = db.session.query(Task.status, db.func.count(Task.id)).group_by(Task.status).all()
    counts = {status: 0 for status in STATUSES}
    counts.update(dict(rows))
    return jsonify(counts=counts, total=sum(counts.values()))


# ------------------------------------------------------ scaling demo


@bp.post("/api/load")
def burn_cpu():
    """Burn CPU for N seconds so a target-tracking policy has something to react to.

    Disabled unless LOAD_ENDPOINT_ENABLED=true. Never enable this in production.
    """
    if not current_app.config["LOAD_ENDPOINT_ENABLED"]:
        return _error("load endpoint disabled", 404)
    try:
        seconds = float(request.args.get("seconds", 20))
    except ValueError:
        return _error("seconds must be a number")
    seconds = max(0.0, min(seconds, current_app.config["LOAD_MAX_SECONDS"]))

    deadline = time.monotonic() + seconds
    digest = b"seed"
    rounds = 0
    while time.monotonic() < deadline:
        digest = hashlib.sha256(digest * 64).digest()
        rounds += 1
    return jsonify(burned_seconds=seconds, rounds=rounds, **instance_info())
