#!/usr/bin/env bash
# Generates CPU load across the fleet so the Auto Scaling target tracking policy fires.
#
#   scripts/load_test.sh <base-url> [workers=24] [duration_seconds=420] [burn_seconds=10]
#
# Each worker sends POST /api/load?seconds=<burn> in a loop. Use the ALB URL (terraform output alb_url)
# from a single machine. Defaults stay below the WAF rate limit (2000 requests / 5 min / IP):
# 24 workers x 1 request per 10 s is about 720 requests per 5 minutes.
set -euo pipefail

base="${1:?usage: load_test.sh <base-url> [workers] [duration_seconds] [burn_seconds]}"
workers="${2:-24}"
duration="${3:-420}"
burn="${4:-10}"
end=$(( $(date +%s) + duration ))

echo "Load test: ${workers} workers, ${burn}s CPU burns, for ${duration}s against ${base}"
echo "Watch the CloudWatch dashboard, or: aws autoscaling describe-scaling-activities --auto-scaling-group-name <asg_name> --max-items 5"

worker() {
  while [ "$(date +%s)" -lt "$end" ]; do
    code=$(curl -s -o /dev/null -m $(( burn + 30 )) -w '%{http_code}' -X POST "${base}/api/load?seconds=${burn}" || echo 000)
    [ "$code" = "200" ] || echo "$(date +%T) unexpected status ${code}"
  done
}

for _ in $(seq "$workers"); do
  worker &
done
wait
echo "Load test finished. Scale-in follows after roughly 15 minutes of low CPU."
