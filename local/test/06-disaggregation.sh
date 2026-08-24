#!/usr/bin/env bash
set -euo pipefail
fail() { echo "FAIL: $1" >&2; exit 1; }

for role in prefill decode; do
  n=$(kubectl -n llm-d get pods -l "llm-d.ai/role=$role" --no-headers 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" -ge 1 ] || fail "no pods labelled llm-d.ai/role=$role"
  kubectl -n llm-d wait --for=condition=Ready pod -l "llm-d.ai/role=$role" --timeout=300s >/dev/null \
    || fail "$role pods never became Ready"
done

pf_node=$(kubectl -n llm-d get pods -l llm-d.ai/role=prefill -o jsonpath='{.items[0].spec.nodeName}')
dc_node=$(kubectl -n llm-d get pods -l llm-d.ai/role=decode  -o jsonpath='{.items[0].spec.nodeName}')
[ -n "$pf_node" ] || fail "could not resolve prefill pod node"
[ -n "$dc_node" ] || fail "could not resolve decode pod node"
[ "$pf_node" != "$dc_node" ] \
  || fail "prefill and decode both landed on $pf_node; KV transfer would not cross the network"

grep -qx prefill <<<"$(kubectl get node "$pf_node" -o jsonpath='{.metadata.labels.llm-d\.ai/pool}')" \
  || fail "prefill pod is not on a pool=prefill node (on $pf_node)"
grep -qx decode <<<"$(kubectl get node "$dc_node" -o jsonpath='{.metadata.labels.llm-d\.ai/pool}')" \
  || fail "decode pod is not on a pool=decode node (on $dc_node)"

body=$(curl -fsS --max-time 30 -X POST localhost:30080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"llm-d-chat","messages":[{"role":"user","content":"hello"}]}') \
  || fail "request failed after P/D split"
echo "$body" | jq -e '.choices[0].message.content' >/dev/null \
  || fail "no completion after P/D split; got: $body"

echo "PASS: prefill and decode separated across nodes, serving end to end"
