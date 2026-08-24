#!/usr/bin/env bash
set -euo pipefail
fail() { echo "FAIL: $1" >&2; exit 1; }

[ -f local/versions.env ] || fail "local/versions.env missing"
# shellcheck disable=SC1091
source local/versions.env

for v in GATEWAY_API_VERSION GAIE_VERSION ISTIO_VERSION INFERENCE_SIM_VERSION \
         LLM_D_INFRA_CHART_VERSION LLM_D_MODELSERVICE_CHART_VERSION INFERENCEPOOL_CHART_VERSION \
         KUBE_PROM_STACK_VERSION MLFLOW_CHART_VERSION ARGOCD_CHART_VERSION; do
  [ -n "${!v:-}" ] || fail "$v is unset"
  case "${!v}" in
    *latest*|*main*|"") fail "$v is not pinned to a concrete version (got '${!v}')" ;;
    # The plan's own Step 4 uses 0.0.0 as an illustrative placeholder. Reject it
    # explicitly - a copied placeholder is the likeliest form of "not pinned",
    # and the latest/main patterns above do not catch it.
    0.0.0|v0.0.0)       fail "$v is still the plan's placeholder value (got '${!v}')" ;;
  esac
done

# Gateway API must be v1.4.0 or newer per llm-d-infra prerequisites
printf '%s\n' "v1.4.0" "$GATEWAY_API_VERSION" | sort -V -C || fail "GATEWAY_API_VERSION below v1.4.0"
echo "PASS: all versions pinned"
