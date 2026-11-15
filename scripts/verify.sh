#!/usr/bin/env bash
# Smoke test: shows load balancing across instances/AZs and exercises the WAF.
#
#   scripts/verify.sh <base-url> [requests=10]
set -euo pipefail

base="${1:?usage: verify.sh <base-url> [requests]}"
n="${2:-10}"

echo "== Load balancing: which instance and AZ answered each request =="
for _ in $(seq "$n"); do
  curl -sI -m 10 "${base}/health" | tr -d '\r' | awk -F': ' 'tolower($1)=="x-served-by"{i=$2} tolower($1)=="x-availability-zone"{z=$2} END{print i, z}'
done | sort | uniq -c

echo
echo "== Application =="
printf 'GET /health        -> %s\n' "$(curl -s -o /dev/null -m 10 -w '%{http_code}' "${base}/health")"
printf 'GET /health/ready  -> %s\n' "$(curl -s -o /dev/null -m 10 -w '%{http_code}' "${base}/health/ready")"
printf 'GET /api/tasks     -> %s\n' "$(curl -s -o /dev/null -m 10 -w '%{http_code}' "${base}/api/tasks")"

echo
echo "== WAF (expect 403 for both attack strings) =="
printf 'XSS in query string -> %s\n' "$(curl -s -o /dev/null -m 10 -w '%{http_code}' -G "${base}/" --data-urlencode 'q=<script>alert(1)</script>')"
printf 'SQLi in query string-> %s\n' "$(curl -s -o /dev/null -m 10 -w '%{http_code}' -G "${base}/api/tasks" --data-urlencode "status=' OR '1'='1")"
printf '/internal/ (ALB rule) -> %s\n' "$(curl -s -o /dev/null -m 10 -w '%{http_code}' "${base}/internal/secrets")"
