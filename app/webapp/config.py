"""Runtime configuration.

Database resolution order:
1. DATABASE_URL            (local development, tests)
2. DB_SECRET_ARN + DB_HOST (AWS: credentials come from the RDS-managed secret)
3. sqlite file             (zero-config fallback for a laptop)
"""
import json
import os
from urllib.parse import quote_plus


def database_uri() -> str:
    url = os.getenv("DATABASE_URL")
    if url:
        return url

    secret_arn = os.getenv("DB_SECRET_ARN")
    host = os.getenv("DB_HOST")
    if secret_arn and host:
        import boto3  # imported lazily so local runs do not need AWS config

        client = boto3.client("secretsmanager", region_name=os.getenv("AWS_REGION"))
        secret = json.loads(client.get_secret_value(SecretId=secret_arn)["SecretString"])
        user = quote_plus(secret["username"])
        password = quote_plus(secret["password"])
        name = os.getenv("DB_NAME", "appdb")
        port = os.getenv("DB_PORT", "5432")
        return f"postgresql+psycopg2://{user}:{password}@{host}:{port}/{name}"

    return "sqlite:///local.db"


def engine_options(uri: str) -> dict:
    options = {"pool_pre_ping": True, "pool_recycle": 280}
    if uri.startswith("postgresql"):
        # RDS PostgreSQL 15+ enforces TLS by default.
        options["connect_args"] = {"sslmode": "require", "connect_timeout": 5}
    return options


class Config:
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    # Static assets get a long browser/CloudFront TTL (CloudFront honours this).
    SEND_FILE_MAX_AGE_DEFAULT = 86400
    APP_VERSION = os.getenv("APP_VERSION", "1.0.0")
    # Demo-only endpoint that burns CPU so you can watch Auto Scaling react.
    LOAD_ENDPOINT_ENABLED = os.getenv("LOAD_ENDPOINT_ENABLED", "false").lower() == "true"
    LOAD_MAX_SECONDS = 120
