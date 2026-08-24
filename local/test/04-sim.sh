#!/usr/bin/env bash
set -euo pipefail
fail() { echo "FAIL: $1" >&2; exit 1; }
cleanup() { kill "${PF_PID:-}" 2>/dev/null || true; }
trap cleanup EXIT

kubectl -n llm-d-smoke rollout status deploy/sim-smoke --timeout=180s >/dev/null 2>&1 || fail "sim-smoke not ready"
kubectl -n llm-d-smoke port-forward svc/sim-smoke 8000:8000 >/dev/null 2>&1 &
PF_PID=$!
for _ in $(seq 1 30); do curl -fsS localhost:8000/health >/dev/null 2>&1 && break; sleep 1; done

body=$(curl -fsS -X POST localhost:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"dummy-model","messages":[{"role":"user","content":"hello"}]}') || fail "chat/completions request failed"
echo "$body" | jq -e '.choices[0].message.content' >/dev/null || fail "no choices[0].message.content in response"

grep -q '^vllm:' <<<"$(curl -fsS localhost:8000/metrics)" || fail "no vllm: prefixed Prometheus metrics on /metrics"
echo "PASS: simulator serves OpenAI API and vLLM metrics"
