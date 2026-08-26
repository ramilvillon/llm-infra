#!/usr/bin/env bash
set -euo pipefail
fail() { echo "FAIL: $1" >&2; exit 1; }

# Guards the "works live, absent from bring-up" defect class that bit this
# plan four times (Task 11 brief, Step 2b) by making the check a committed
# test instead of a one-off grep run by hand once. Runs on every `make test`
# (globbed from local/test/*.sh) so a future task deleting any of these
# Makefile lines is caught at the next `make test`, not the next cold rebuild.
mk="local/Makefile"
[ -f "$mk" ] || fail "$mk missing"

grep -q 'ENABLE_GATEWAY_API_INFERENCE_EXTENSION=true' "$mk" \
  || fail "istioctl install no longer sets the inference-extension flag - Istio would silently reject InferencePool backendRefs and bypass the EPP"
grep -q 'inferenceobjective-crd.yaml' "$mk" \
  || fail "make up no longer applies the InferenceObjective CRD - the EPP would crashloop"
grep -q 'llm-d-pools-podmonitor.yaml' "$mk" \
  || fail "make up no longer applies the pools PodMonitor - Prometheus would scrape neither pool"
grep -q 'llm-d-serving-dashboard' "$mk" \
  || fail "make up no longer provisions the Grafana dashboard ConfigMap - the dashboard would never render"
grep -q 'oci://registry.k8s.io/gateway-api-inference-extension/charts/inferencepool' "$mk" \
  || fail "make up no longer installs the InferencePool/EPP chart - the gateway would round-robin with no EPP in the request path"

echo "PASS: Makefile up target contains all bring-up-gap artifacts and the InferencePool chart install"

# Topology purity: charts/llm-d/modelservice-values-common.yaml must stay
# byte-identical across local/poc/prod. Enforce the file's own header comment
# as a runnable guard instead of trusting it stays true by convention -
# strip comment lines first so prose mentioning these words (the header
# itself does) cannot false-positive; match actual YAML keys only.
common="charts/llm-d/modelservice-values-common.yaml"
[ -f "$common" ] || fail "$common missing"
stripped=$(grep -v '^[[:space:]]*#' "$common")

grep -qE '^[[:space:]]*(- )?image:' <<<"$stripped" \
  && fail "$common contains 'image:' - a container image is environment-specific (poc/prod won't use the simulator) and belongs in modelservice-values-<env>.yaml"
grep -qE '^[[:space:]]*(- )?nodeSelector:' <<<"$stripped" \
  && fail "$common contains 'nodeSelector:' - node scheduling labels differ per environment's node pools and belong in modelservice-values-<env>.yaml"
grep -qE '^[[:space:]]*(- )?replicas:' <<<"$stripped" \
  && fail "$common contains 'replicas:' - replica counts are a per-environment scaling decision and belong in modelservice-values-<env>.yaml"
grep -qE '^[[:space:]]*(- )?accelerator:' <<<"$stripped" \
  && fail "$common contains 'accelerator:' - accelerator type (cpu here, gpu on AWS) is environment-specific hardware and belongs in modelservice-values-<env>.yaml"
grep -qE '^[[:space:]]*(- )?resources:' <<<"$stripped" \
  && fail "$common contains 'resources:' - resource requests/limits are environment-specific sizing and belong in modelservice-values-<env>.yaml"

echo "PASS: modelservice-values-common.yaml contains no environment-specific keys"
