#!/usr/bin/env bash
set -euo pipefail
fail() { echo "FAIL: $1" >&2; exit 1; }

kubectl get ns llm-d >/dev/null 2>&1 || fail "namespace llm-d missing"
kubectl -n llm-d get gateway >/dev/null 2>&1 || fail "no Gateway in namespace llm-d"
kubectl -n llm-d wait --for=condition=Programmed gateway --all --timeout=180s >/dev/null \
  || fail "gateway never became Programmed"

dc=$(kubectl -n llm-d get pods -l llm-d.ai/role=decode --no-headers 2>/dev/null | wc -l | tr -d ' ')
[ "$dc" -ge 1 ] || fail "no pods labelled llm-d.ai/role=decode"
kubectl -n llm-d wait --for=condition=Ready pod -l llm-d.ai/role=decode --timeout=300s >/dev/null \
  || fail "decode pods never became Ready"

# The EPP scheduler must exist AND be in the request path. Without these three
# assertions the gateway silently round-robins, which looks healthy and defeats
# the entire purpose of running llm-d.
kubectl -n llm-d get inferencepool >/dev/null 2>&1 || fail "no InferencePool - EPP scheduler is absent"
ip_name=$(kubectl -n llm-d get inferencepool -o jsonpath='{.items[0].metadata.name}')
[ -n "$ip_name" ] || fail "InferencePool exists but has no name"

epp_ready=$(kubectl -n llm-d get pods -o json \
  | jq -r '[.items[] | select(.metadata.name | test("epp")) | select(.status.phase=="Running")] | length')
[ "${epp_ready:-0}" -ge 1 ] || fail "no running EPP pod"

# backendRef must target the InferencePool, not a plain Service. If it targets a
# Service the EPP is installed but never consulted.
backend_kind=$(kubectl -n llm-d get httproute -o jsonpath='{.items[0].spec.rules[0].backendRefs[0].kind}')
[ "$backend_kind" = "InferencePool" ] \
  || fail "HTTPRoute backendRef kind is '$backend_kind', expected InferencePool - EPP is bypassed"

body=$(curl -fsS --max-time 30 -X POST localhost:30080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"dummy-model","messages":[{"role":"user","content":"hello"}]}') \
  || fail "request through gateway failed"
echo "$body" | jq -e '.choices[0].message.content' >/dev/null \
  || fail "no completion returned through gateway; got: $body"

echo "PASS: request routed through gateway to a decode pod"
