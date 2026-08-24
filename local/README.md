# local — one-command llm-d developer stack

A full local llm-d stack on `kind`: Istio Gateway -> EPP scheduler ->
separate prefill/decode pools (`llm-d-inference-sim`, no GPUs required),
Prometheus scraping both pools, a four-panel Grafana dashboard, MLflow, and
four ArgoCD Applications syncing from this repo.

## Prerequisites

Installed and on `PATH` (verified by `test/00-toolchain.sh`):

- `colima` (Docker runtime for macOS)
- `docker` (CLI, via colima's socket)
- `kind`
- `kubectl`
- `helm` >= 3.10
- `istioctl`
- `jq`
- `yq`
- `gh`

colima needs at least 6 CPUs, 12GB RAM, and 60GB disk:
`colima start --cpu 6 --memory 12 --disk 60` (`make up` does this for you if
colima isn't already running).

## Make targets

- **`make up`** — starts colima if needed, creates the `llm-d-local` kind
  cluster, installs the Gateway API and GAIE CRDs, Istio (with the
  inference-extension feature flag), ArgoCD, and the InferencePool/EPP
  chart (the one piece deliberately kept outside ArgoCD — see
  `../.superpowers/sdd/2026-08-24-phase-0-local-stack/task-10-report.md`),
  applies the four ArgoCD Applications that own everything else, and
  provisions the pools PodMonitor and the Grafana dashboard ConfigMap.
  Idempotent — safe to re-run against an already-up cluster.
- **`make test`** — runs every script in `test/*.sh` against the live
  cluster and prints `ALL PASS` on success.
- **`make load`** — fires 50 concurrent chat-completion requests at the
  gateway so the Grafana dashboard has something to show.
- **`make down`** — deletes the kind cluster, including the MLflow PVC and
  its experiments (expected — they're verification artifacts, not real
  data).
- **`make reset`** — `down` then `up`.

## Endpoints (NodePorts, loopback-only)

| Port | Service |
|---|---|
| `localhost:30080` | Gateway (OpenAI-compatible `/v1/chat/completions`) |
| `localhost:30300` | Grafana (`admin` / `admin`) |
| `localhost:30500` | MLflow tracking server |

These are bound to `127.0.0.1` only (see `kind-config.yaml`), not `0.0.0.0`
— they are not reachable from other devices on the same network.

## Try it

```bash
cd local
make up
make test
curl -s localhost:30080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"dummy-model","messages":[{"role":"user","content":"hello"}]}' | jq .
make load   # then open http://localhost:30300
```

## Notes

- `versions.env` pins every chart/CRD/binary version this stack uses.
  Source it, never hardcode a version.
- `manifests/` holds the CRDs and objects that no Helm chart declares
  (InferenceObjective CRD, pools PodMonitor) and Task 4's simulator smoke
  manifest.
- Running on Apple Silicon and hit a slow-starting or amd64-only image? See
  `ARM64-NOTES.md`.
- **What this stack does not prove**: the prefill pool never serves traffic
  in Phase 0 (`routing.proxy.enabled` is `false`), so the dashboard's
  TTFT/TPOT panels show only a decode series. This stack proves the
  *topology* — two independently-scaled, correctly-scheduled, separately-
  scraped pools with cache-aware routing genuinely in the request path —
  not the prefill/decode traffic split. That needs real vLLM on real GPUs
  (Phase 2).
