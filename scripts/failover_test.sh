#!/usr/bin/env bash
# Forces an RDS Multi-AZ failover and prints application health every 3 seconds.
#
#   scripts/failover_test.sh <rds-identifier> <base-url>
#
# Expected: /health stays 200 the whole time (the ALB keeps all targets), while /health/ready
# turns 503 for roughly 60-120 seconds (database unreachable), then returns to 200 on the new primary.
# Stop with Ctrl-C.
set -euo pipefail

db="${1:?usage: failover_test.sh <rds-identifier> <base-url>}"
base="${2:?usage: failover_test.sh <rds-identifier> <base-url>}"

echo "$(date +%T) requesting failover of ${db}"
aws rds reboot-db-instance --db-instance-identifier "$db" --force-failover --query 'DBInstance.DBInstanceStatus' --output text

while true; do
  live=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "${base}/health" || echo 000)
  ready=$(curl -s -o /dev/null -m 5 -w '%{http_code}' "${base}/health/ready" || echo 000)
  echo "$(date +%T)  /health=${live}  /health/ready=${ready}"
  sleep 3
done
