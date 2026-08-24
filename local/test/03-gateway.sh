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

# InferenceObjective CRD - the EPP will not start without it. Not part of the
# GAIE v1.6.0 release bundles; vendored separately at local/manifests/inferenceobjective-crd.yaml.
kubectl get crd inferenceobjectives.inference.networking.x-k8s.io >/dev/null 2>&1 \
  || fail "InferenceObjective CRD missing - EPP will crashloop"

# The istiod feature flag. Without it Istio silently rejects InferencePool
# backendRefs and the EPP is bypassed entirely. It is off by default and
# `istioctl install --set profile=minimal` alone does not set it. Asserting it
# here is what makes a cold rebuild (`make down && make up`) safe.
flag=$(kubectl -n istio-system get deploy istiod \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="ENABLE_GATEWAY_API_INFERENCE_EXTENSION")].value}')
[ "$flag" = "true" ] \
  || fail "istiod is missing ENABLE_GATEWAY_API_INFERENCE_EXTENSION=true (got '$flag'); InferencePool backendRefs will be rejected"

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
