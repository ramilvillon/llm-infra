#!/usr/bin/env bash
set -euo pipefail
fail() { echo "FAIL: $1" >&2; exit 1; }

# Name the resource. `rollout status deploy` with NO name prints "No resources found"
# and exits 0, so it passes against a missing namespace entirely - proven: nameless
# exit=0, named exit=1 against a nonexistent namespace.
kubectl -n mlflow rollout status deploy/mlflow --timeout=300s >/dev/null 2>&1 || fail "mlflow not ready"
curl -fsS localhost:30500/health >/dev/null 2>&1 || curl -fsS localhost:30500/ >/dev/null 2>&1 \
  || fail "mlflow not reachable on :30500"

exp=$(curl -fsS -X POST localhost:30500/api/2.0/mlflow/experiments/create \
  -H 'Content-Type: application/json' \
  -d '{"name":"smoke-'"$RANDOM"'"}') || fail "cannot create experiment via REST API"
echo "$exp" | jq -e '.experiment_id' >/dev/null || fail "no experiment_id returned"
echo "PASS: mlflow tracking server accepting experiments"
