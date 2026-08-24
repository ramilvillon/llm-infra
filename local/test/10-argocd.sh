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

  # A wrong or missing helm.releaseName renders duplicate, differently-named
  # resources beside the orphaned originals - and the Application still
  # reports Synced/Healthy, so the checks above would still pass. Prove the
  # pin actually names a Helm release that exists in the target namespace.
  rel=$(kubectl -n argocd get application "$app" -o jsonpath='{.spec.sources[0].helm.releaseName}' 2>/dev/null || true)
  ns=$(kubectl -n argocd get application "$app" -o jsonpath='{.spec.destination.namespace}' 2>/dev/null || true)
  [ -n "$rel" ] || fail "$app has no helm.releaseName pinned"
  [ -n "$ns" ]  || fail "$app has no destination.namespace"
  helm -n "$ns" status "$rel" >/dev/null 2>&1 || fail "$app's releaseName '$rel' is not a live helm release in namespace '$ns'"
done
echo "PASS: all four applications synced and healthy, releaseName pins verified live"
