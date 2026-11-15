"""EC2 instance metadata (IMDSv2) so each response can show which node served it."""
import functools
import socket
import urllib.request

IMDS = "http://169.254.169.254/latest"


def _get(path: str, token: str | None = None, method: str = "GET") -> str:
    headers = {}
    if method == "PUT":
        headers["X-aws-ec2-metadata-token-ttl-seconds"] = "300"
    elif token:
        headers["X-aws-ec2-metadata-token"] = token
    request = urllib.request.Request(f"{IMDS}/{path}", method=method, headers=headers)
    with urllib.request.urlopen(request, timeout=0.5) as response:  # noqa: S310 (fixed link-local URL)
        return response.read().decode()


@functools.lru_cache(maxsize=1)
def instance_info() -> dict:
    try:
        token = _get("api/token", method="PUT")
        return {
            "instance_id": _get("meta-data/instance-id", token),
            "availability_zone": _get("meta-data/placement/availability-zone", token),
            "instance_type": _get("meta-data/instance-type", token),
            "source": "imds",
        }
    except Exception:
        return {
            "instance_id": socket.gethostname(),
            "availability_zone": "local",
            "instance_type": "local",
            "source": "fallback",
        }
