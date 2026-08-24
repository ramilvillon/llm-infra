#!/usr/bin/env bash
set -euo pipefail
fail() { echo "FAIL: $1" >&2; exit 1; }
cleanup() { kill "${PF_PID:-}" 2>/dev/null || true; }
trap cleanup EXIT

# Every promql metric referenced by the dashboard must exist in the captured set.
# That file is a LOWER BOUND (the exporter registers metrics lazily), so a miss means
# "verify this metric is real", not necessarily "this metric does not exist".
# metrics-available.txt records HELP lines under the histogram's base name only -
# it never lists the _bucket/_sum/_count series a histogram expands into at scrape
# time - so strip those suffixes before checking.
while read -r m; do
  base="${m%_bucket}"; base="${base%_sum}"; base="${base%_count}"
  grep -q "$base" local/metrics-available.txt \
    || fail "dashboard references '$m', base metric '$base' absent from local/metrics-available.txt - confirm it is real and re-capture, or fix the query"
done < <(jq -r '.panels[].targets[].expr' charts/observability/dashboards/llm-d-serving.json \
         | grep -oE 'vllm:[a-z_]+' | sort -u)

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
