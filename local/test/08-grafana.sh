#!/usr/bin/env bash
set -euo pipefail
fail() { echo "FAIL: $1" >&2; exit 1; }
cleanup() { kill "${PF_PID:-}" 2>/dev/null || true; }
trap cleanup EXIT

# Every promql metric referenced by the dashboard must exist in the captured set.
# That file is a LOWER BOUND (the exporter registers metrics lazily), so a miss means
# "verify this metric is real", not necessarily "this metric does not exist".
#
# Capture the list FIRST and assert it is non-empty. A `while read < <(producer)` over
# empty input runs zero iterations and silently passes - the check would be vacuous
# exactly when the dashboard is malformed.
metrics=$(jq -r '.panels[].targets[].expr' charts/observability/dashboards/llm-d-serving.json \
          | grep -oE 'vllm:[a-z_]+' | sort -u || true)
[ -n "$metrics" ] || fail "extracted no vllm: metric names from the dashboard - malformed JSON or wrong query syntax"

while read -r m; do
  # Histogram suffixes are NOT in metrics-available.txt (it records only HELP base
  # names), so they must be stripped - but ONLY when the base is genuinely a histogram.
  # Stripping unconditionally would let a hallucinated 'vllm:num_requests_waiting_bucket'
  # pass by matching the Gauge 'vllm:num_requests_waiting', rendering an empty panel with
  # no error - precisely the failure this check exists to prevent.
  case "$m" in
    *_bucket|*_sum|*_count)
      base="${m%_bucket}"; base="${base%_sum}"; base="${base%_count}"
      grep -q "HELP $base Histogram" <<<"$(cat local/metrics-available.txt)" \
        || fail "dashboard uses histogram suffix on '$m', but '$base' is not a Histogram in local/metrics-available.txt"
      ;;
    *)
      grep -q "$m" <<<"$(cat local/metrics-available.txt)" \
        || fail "dashboard references '$m', absent from local/metrics-available.txt - confirm it is real and re-capture, or fix the query"
      ;;
  esac
done <<<"$metrics"

# Every panel must break down by pool (llm_d_ai_role) - otherwise it is useless for P/D sizing.
panel_count=$(jq -e '.panels | length' charts/observability/dashboards/llm-d-serving.json) \
  || fail "dashboard has no panels"
[ "$panel_count" -eq 4 ] || fail "expected 4 panels, found $panel_count"
grouped_count=$(jq -r '.panels[].targets[].expr' charts/observability/dashboards/llm-d-serving.json \
  | grep -c 'by (le, llm_d_ai_role)\|by (llm_d_ai_role)') || fail "no query groups by llm_d_ai_role"
[ "$grouped_count" -eq 4 ] || fail "expected all 4 panel queries to group by llm_d_ai_role, found $grouped_count"

kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80 >/dev/null 2>&1 &
PF_PID=$!
for _ in $(seq 1 30); do curl -fsS localhost:3000/api/health >/dev/null 2>&1 && break; sleep 1; done

dash=$(curl -fsS -u admin:admin localhost:3000/api/dashboards/uid/llm-d-serving) \
  || fail "cannot fetch dashboard uid llm-d-serving from grafana api"
jq -e '.dashboard.title' <<<"$dash" >/dev/null || fail "dashboard uid llm-d-serving not provisioned"
jq -e '.dashboard.uid == "llm-d-serving"' <<<"$dash" >/dev/null \
  || fail "provisioned dashboard uid does not match llm-d-serving"

echo "PASS: grafana dashboard provisioned with only real metrics"
