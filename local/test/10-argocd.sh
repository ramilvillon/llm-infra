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
  # pin actually took effect.
  #
  # NOT via `helm status`: ArgoCD's Helm chart sources render through an
  # internal `helm template` and apply the result as plain manifests - it
  # never runs `helm install`/`helm upgrade`, so no `sh.helm.release.v1.*`
  # Secret is ever created and `helm status` can never succeed here,
  # regardless of correctness. Confirmed empirically on a genuinely cold
  # `make up` (Task 11): `helm list -A` afterward shows only the two
  # releases the Makefile installs via the literal Helm CLI (argocd,
  # llm-d-ip) - never these four ArgoCD-managed ones, even though all four
  # are Synced/Healthy with the right resources live. The original
  # `helm status` check was only ever passing because Tasks 5-9 had
  # already `helm install`-ed these releases by hand before Task 10 pointed
  # ArgoCD at them for adoption - a hand-adopted cluster, not a cold one.
  #
  # Verify instead against ArgoCD's own tracked-resources list (always
  # populated for a Synced app, independent of chart or Helm-CLI internals)
  # that resources were NOT rendered under the wrong default release name -
  # the actual failure mode this check exists to catch. If `helm.releaseName`
  # were unset, ArgoCD defaults the release name to the Application's own
  # `metadata.name`, and any chart following the standard
  # `{{ .Release.Name }}-xxx` naming convention would then render resources
  # prefixed with the Application name instead of the pinned release name.
  rel=$(kubectl -n argocd get application "$app" -o jsonpath='{.spec.sources[0].helm.releaseName}' 2>/dev/null || true)
  ns=$(kubectl -n argocd get application "$app" -o jsonpath='{.spec.destination.namespace}' 2>/dev/null || true)
  [ -n "$rel" ] || fail "$app has no helm.releaseName pinned"
  [ -n "$ns" ]  || fail "$app has no destination.namespace"

  resources=$(kubectl -n argocd get application "$app" -o jsonpath='{.status.resources}')
  [ -n "$resources" ] && [ "$resources" != "[]" ] || fail "$app has no tracked resources"

  # Only meaningful when releaseName differs from the Application name -
  # when they coincide (mlflow, llm-d-infra) there is no naming collision to
  # distinguish, same no-op-safety-net case already documented in
  # mlflow.yaml. Restricted to Deployment/StatefulSet: this project pins
  # several OTHER resource names (the Gateway's fullnameOverride, the
  # HTTPRoute's fixed name in modelservice-values-common.yaml) independently
  # of the release name for cross-chart referencing, so a name check across
  # ALL tracked resources false-positives on those. Deployment/StatefulSet
  # names are confirmed (live, all four charts) to always follow Helm's
  # `{{ .Release.Name }}-...` convention here, so they are the reliable signal.
  if [ "$rel" != "$app" ]; then
    workload_names=$(echo "$resources" | jq -r '.[] | select(.kind=="Deployment" or .kind=="StatefulSet") | .name')
    [ -n "$workload_names" ] || fail "$app has no tracked Deployment/StatefulSet to verify the releaseName pin against"
    while read -r wname; do
      case "$wname" in
        "$rel"|"$rel"-*) ;;
        *) fail "$app's workload '$wname' is not prefixed with pinned releaseName '$rel' - helm.releaseName pin did not take effect" ;;
      esac
    done <<<"$workload_names"
  fi
done
echo "PASS: all four applications synced and healthy, releaseName pins verified live"
