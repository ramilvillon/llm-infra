#!/usr/bin/env bash
set -euo pipefail
fail() { echo "FAIL: $1" >&2; exit 1; }

kubectl config use-context kind-llm-d-local >/dev/null 2>&1 || fail "context kind-llm-d-local missing"
[ "$(kubectl get nodes --no-headers | wc -l | tr -d ' ')" -eq 3 ] || fail "expected 3 nodes"
kubectl get nodes -l llm-d.ai/pool=prefill --no-headers | grep -q . || fail "no node labelled pool=prefill"
kubectl get nodes -l llm-d.ai/pool=decode  --no-headers | grep -q . || fail "no node labelled pool=decode"
kubectl get nodes -o jsonpath='{.items[*].status.nodeInfo.kubeletVersion}' | grep -qE 'v1\.(2[89]|[3-9][0-9])' || fail "kubelet below v1.28"

# Ports must be loopback-only. A 0.0.0.0 binding exposes the gateway, Grafana
# and MLflow to every host on the local network.
for port in 30080 30300 30500; do
  docker port llm-d-local-control-plane "$port" 2>/dev/null | grep -q '^127\.0\.0\.1:' \
    || fail "port $port is not bound to 127.0.0.1 (got: $(docker port llm-d-local-control-plane "$port" 2>/dev/null || echo unmapped))"
done

echo "PASS: cluster ready"
