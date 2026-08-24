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

# All three are hard failures. Later tasks are entitled to assume Task 0
# verified this sizing, so a warning here would make that guarantee hollow.
read -r cpus mem disk < <(colima list --json | jq -r 'select(.name=="default") | "\(.cpus) \(.memory) \(.disk)"')
[ "${cpus:-0}" -ge 6 ]           || fail "colima has ${cpus:-?} CPUs, need 6"
[ "${mem:-0}"  -ge 12000000000 ] || fail "colima has ${mem:-?} bytes RAM, need ~12GB"
[ "${disk:-0}" -ge 60000000000 ] || fail "colima has ${disk:-?} bytes disk, need 60GB"

echo "PASS: toolchain present and colima running"
