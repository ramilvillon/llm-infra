#!/usr/bin/env bash
set -euo pipefail
fail() { echo "FAIL: $1" >&2; exit 1; }
cleanup() { kill "${PF_PID:-}" 2>/dev/null || true; }
trap cleanup EXIT

kubectl -n monitoring rollout status statefulset/prometheus-kube-prometheus-stack-prometheus --timeout=300s >/dev/null 2>&1 \
  || fail "prometheus not ready"

kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090 >/dev/null 2>&1 &
PF_PID=$!
for _ in $(seq 1 30); do curl -fsS localhost:9090/-/ready >/dev/null 2>&1 && break; sleep 1; done

targets=$(curl -fsS 'localhost:9090/api/v1/targets?state=active') || fail "cannot query targets"
echo "$targets" | jq -e '[.data.activeTargets[] | select(.labels.namespace=="llm-d")] | length >= 2' >/dev/null \
  || fail "fewer than 2 active llm-d targets - both pools should be scraped"
echo "$targets" | jq -e '[.data.activeTargets[] | select(.labels.namespace=="llm-d" and .health=="up")] | length >= 2' >/dev/null \
  || fail "llm-d targets are not healthy"

series=$(curl -fsS --get localhost:9090/api/v1/label/__name__/values) || fail "cannot list metric names"
echo "$series" | jq -e '[.data[] | select(startswith("vllm:"))] | length > 0' >/dev/null \
  || fail "no vllm: metrics ingested"

roles=$(curl -fsS --get localhost:9090/api/v1/query --data-urlencode 'query=count by (llm_d_ai_role) (up{namespace="llm-d"})') \
  || fail "cannot query llm_d_ai_role label"
echo "$roles" | jq -e '[.data.result[].metric.llm_d_ai_role] | sort == ["decode","prefill"]' >/dev/null \
  || fail "llm_d_ai_role label not present on both pools - relabeling missing or broken: $roles"

echo "PASS: prometheus scraping both pools with vllm metrics and llm_d_ai_role label present"
