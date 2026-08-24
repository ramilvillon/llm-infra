#!/usr/bin/env bash
set -euo pipefail
fail() { echo "FAIL: $1" >&2; exit 1; }

kubectl -n argocd rollout status deploy/argocd-server --timeout=300s >/dev/null 2>&1 || fail "argocd-server not ready"
for app in llm-d-infra llm-d observability mlflow; do
  kubectl -n argocd get application "$app" >/dev/null 2>&1 || fail "Application '$app' missing"
  sync=$(kubectl -n argocd get application "$app" -o jsonpath='{.status.sync.status}')
  health=$(kubectl -n argocd get application "$app" -o jsonpath='{.status.health.status}')
  [ "$sync" = "Synced" ]     || fail "$app sync status is '$sync', expected Synced"
  [ "$health" = "Healthy" ]  || fail "$app health is '$health', expected Healthy"
done
echo "PASS: all four applications synced and healthy"
