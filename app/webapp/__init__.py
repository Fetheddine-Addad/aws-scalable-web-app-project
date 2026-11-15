import logging
import time

from flask import Flask, jsonify
from sqlalchemy import text

from .config import Config, database_uri, engine_options
from .instance import instance_info
from .models import db
from .routes import bp

log = logging.getLogger(__name__)


def _init_schema(app: Flask) -> None:
    """Create tables once, even when several new instances boot at the same time."""
    for attempt in range(1, 7):
        try:
            with app.app_context():
                is_postgres = db.engine.dialect.name == "postgresql"
                if is_postgres:
                    # Advisory lock serialises create_all across concurrently launching instances.
                    with db.engine.begin() as conn:
                        conn.execute(text("SELECT pg_advisory_xact_lock(727274)"))
                        db.metadata.create_all(conn)
                else:
                    db.create_all()
            return
        except Exception as exc:  # noqa: BLE001
            log.warning("schema init attempt %s failed: %s", attempt, exc)
            time.sleep(min(2 * attempt, 10))
    log.error("schema init failed; /health/ready will report degraded until the database is reachable")


def create_app(test_config: dict | None = None) -> Flask:
    app = Flask(__name__)
    app.config.from_object(Config)

    if test_config:
        app.config.update(test_config)
    uri = app.config.get("SQLALCHEMY_DATABASE_URI") or database_uri()
    app.config["SQLALCHEMY_DATABASE_URI"] = uri
    app.config.setdefault("SQLALCHEMY_ENGINE_OPTIONS", engine_options(uri))

    db.init_app(app)
    app.register_blueprint(bp)
    _init_schema(app)

    @app.after_request
    def add_headers(response):
        # Lets you prove load balancing: curl -sI <url> | grep -i x-served-by
        info = instance_info()
        response.headers["X-Served-By"] = info["instance_id"]
        response.headers["X-Availability-Zone"] = info["availability_zone"]
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        return response

    @app.errorhandler(404)
    def not_found(_):
        return jsonify(error="not found"), 404

    @app.errorhandler(500)
    def server_error(_):
        return jsonify(error="internal server error"), 500

    return app
