#!/usr/bin/env bash
set -euo pipefail
fail() { echo "FAIL: $1" >&2; exit 1; }

for t in colima kind kubectl helm istioctl yq jq gh docker; do
  command -v "$t" >/dev/null 2>&1 || fail "$t not on PATH"
done

# Helm 3.10+ per Global Constraints
hv=$(helm version --template '{{.Version}}' | sed 's/^v//')
printf '%s\n' "3.10.0" "$hv" | sort -V -C || fail "helm $hv is below 3.10"

colima status >/dev/null 2>&1 || fail "colima VM is not running"
docker info >/dev/null 2>&1 || fail "docker socket unreachable - colima not providing it"

mem=$(colima list --json 2>/dev/null | jq -r 'select(.name=="default") | .memory' || echo 0)
[ "${mem:-0}" -ge 11000000000 ] 2>/dev/null || echo "WARN: colima memory is ${mem:-unknown}; the stack needs ~12GB"

echo "PASS: toolchain present and colima running"
