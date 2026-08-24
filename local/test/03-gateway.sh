#!/usr/bin/env bash
set -euo pipefail
fail() { echo "FAIL: $1" >&2; exit 1; }

source "$(dirname "${BASH_SOURCE[0]}")/../versions.env"

kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1 || fail "Gateway API CRDs missing"
# Capture output before grepping: `kubectl get crd | grep -q ...` is flaky under
# pipefail because grep -q can close the pipe early and SIGPIPE kubectl (exit 141),
# failing the pipeline even when the CRD is present.
crd_list="$(kubectl get crd)"
grep -q inferencepools <<<"$crd_list" || fail "GAIE InferencePool CRD missing"
kubectl -n istio-system get deploy istiod >/dev/null 2>&1 || fail "istiod not installed"
kubectl -n istio-system rollout status deploy/istiod --timeout=180s >/dev/null || fail "istiod not ready"
kubectl get gatewayclass istio >/dev/null 2>&1 || fail "GatewayClass 'istio' missing"

# Istio's `istioctl install` uses the version compiled into the istioctl binary,
# not $ISTIO_VERSION - so a `brew upgrade istioctl` can silently drift from the
# pinned version with nothing to catch it. Assert the running control plane
# matches the pin.
istiod_image="$(kubectl -n istio-system get deploy istiod -o jsonpath='{.spec.template.spec.containers[0].image}')"
istiod_tag="${istiod_image##*:}"
istiod_tag="${istiod_tag#v}"
pinned_version="${ISTIO_VERSION#v}"
[ -n "$istiod_tag" ] || fail "could not determine istiod image tag from '$istiod_image'"
[ "$istiod_tag" = "$pinned_version" ] || fail "istiod running version '$istiod_tag' does not match pinned ISTIO_VERSION '$pinned_version'"

echo "PASS: gateway layer ready"
