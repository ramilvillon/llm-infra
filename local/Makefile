# local/Makefile - one-command developer interface for the local llm-d stack.
#
# `up` replays every artifact that earlier tasks applied by hand against the
# live cluster (istiod inference-extension flag, InferenceObjective CRD,
# pools PodMonitor, Grafana dashboard ConfigMap, ArgoCD itself, its four
# Applications, and the InferencePool/EPP chart, which stays outside ArgoCD
# because Task 10 scoped GitOps to four Applications - see the "Follow-up
# deferred" note in the plan for wiring it in as a fifth, sync-wave-0
# Application). None of those are optional: omit any one and the
# corresponding test/*.sh fails on a cold rebuild even though it would have
# passed against the long-lived hand-tuned cluster (this bit four times:
# the istiod flag, the InferenceObjective CRD, the pools PodMonitor, and the
# Grafana dashboard ConfigMap - each was once applied by hand, passed its
# own task's test, and would have vanished on rebuild). Anything applied
# with an imperative kubectl/helm command, not a Helm release ArgoCD tracks,
# must be replayed here AND gated by local/test/11-makefile-gates.sh.
SHELL := /usr/bin/env bash
.PHONY: up down test load reset

up:
	colima status >/dev/null 2>&1 || colima start --cpu 6 --memory 12 --disk 60
	kind get clusters | grep -qx llm-d-local || { set -a && source versions.env && set +a && \
	  kcfg=$$(mktemp) && sed -e "s|KIND_NODE_IMAGE|$$KIND_NODE_IMAGE|" kind-config.yaml > "$$kcfg" && \
	  kind create cluster --config "$$kcfg" && rm -f "$$kcfg"; }
	helm repo add llm-d-infra https://llm-d-incubation.github.io/llm-d-infra/ >/dev/null
	helm repo add llm-d-modelservice https://llm-d-incubation.github.io/llm-d-modelservice/ >/dev/null
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
	helm repo add community-charts https://community-charts.github.io/helm-charts >/dev/null
	helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
	helm repo update >/dev/null
	set -a && source versions.env && set +a && \
	kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/$$GATEWAY_API_VERSION/standard-install.yaml" && \
	kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api-inference-extension/releases/download/$$GAIE_VERSION/manifests.yaml" && \
	kubectl apply -f manifests/inferenceobjective-crd.yaml && \
	istioctl install --set profile=minimal \
	  --set values.pilot.env.ENABLE_GATEWAY_API_INFERENCE_EXTENSION=true -y && \
	helm upgrade --install argocd argo/argo-cd --version $$ARGOCD_CHART_VERSION \
	  --namespace argocd --create-namespace --wait --timeout 10m && \
	kubectl create namespace llm-d --dry-run=client -o yaml | kubectl apply -f - && \
	for f in ../argocd/applications/*.yaml; do \
	  echo "---"; \
	  sed -e "s|LLM_D_INFRA_CHART_VERSION|$$LLM_D_INFRA_CHART_VERSION|" \
	      -e "s|LLM_D_MODELSERVICE_CHART_VERSION|$$LLM_D_MODELSERVICE_CHART_VERSION|" \
	      -e "s|KUBE_PROM_STACK_VERSION|$$KUBE_PROM_STACK_VERSION|" \
	      -e "s|MLFLOW_CHART_VERSION|$$MLFLOW_CHART_VERSION|" \
	      -e "s|GIT_REVISION|$$GIT_REVISION|" "$$f"; \
	done | kubectl apply -f - && \
	helm upgrade --install llm-d-ip oci://registry.k8s.io/gateway-api-inference-extension/charts/inferencepool \
	  --version $$INFERENCEPOOL_CHART_VERSION -n llm-d --create-namespace \
	  -f ../charts/llm-d/inferencepool-values-local.yaml --wait --timeout 10m
	@echo "Waiting for all four ArgoCD Applications to reach sync status Synced..."
	@ready=0; \
	for i in $$(seq 1 90); do \
	  synced=1; \
	  for app in llm-d-infra llm-d observability mlflow; do \
	    s=$$(kubectl -n argocd get application "$$app" -o jsonpath='{.status.sync.status}' 2>/dev/null || true); \
	    [ "$$s" = "Synced" ] || synced=0; \
	  done; \
	  [ "$$synced" -eq 1 ] && { ready=1; break; }; \
	  sleep 5; \
	done; \
	[ "$$ready" -eq 1 ] || { echo "ERROR: not all four ArgoCD Applications reached Synced after 450s"; kubectl -n argocd get applications; exit 1; }
	@echo "Waiting for the observability Application to sync (provides the PodMonitor CRD and 'monitoring' namespace)..."
	@ready=0; \
	for i in $$(seq 1 90); do \
	  kubectl get ns monitoring >/dev/null 2>&1 && kubectl get crd podmonitors.monitoring.coreos.com >/dev/null 2>&1 && { ready=1; break; }; \
	  sleep 5; \
	done; \
	[ "$$ready" -eq 1 ] || { echo "ERROR: observability Application never synced - 'monitoring' namespace or PodMonitor CRD absent after 450s"; exit 1; }
	kubectl apply -f manifests/llm-d-pools-podmonitor.yaml
	kubectl -n monitoring create configmap llm-d-serving-dashboard \
	  --from-file=llm-d-serving.json=../charts/observability/dashboards/llm-d-serving.json \
	  --dry-run=client -o yaml \
	  | kubectl label -f - grafana_dashboard=1 --local -o yaml \
	  | kubectl apply -f -
	@echo "Waiting for EPP ext-proc listener (readinessProbe checks :9003, but Envoy calls :9002)..."
	@ready=0; \
	for i in $$(seq 1 60); do \
	  kubectl -n llm-d logs -l inferencepool=llm-d-ip-epp --tail=50 2>/dev/null | grep -q 9002 && { ready=1; break; }; \
	  sleep 2; \
	done; \
	[ "$$ready" -eq 1 ] || { echo "ERROR: EPP ext-proc listener on :9002 never appeared in logs after 120s - InferencePool backendRefs would be rejected or the EPP never came up"; exit 1; }
	@echo "ArgoCD now owns llm-d-infra, llm-d, observability, and mlflow. Run 'make test' once sync completes."

test:
	@cd .. && for t in local/test/*.sh; do echo "--- $$t"; bash "$$t" || exit 1; done
	@echo "ALL PASS"

load:
	@for i in $$(seq 1 50); do \
	  curl -fsS -X POST localhost:30080/v1/chat/completions \
	    -H 'Content-Type: application/json' \
	    -d '{"model":"llm-d-chat","messages":[{"role":"user","content":"hello"}],"max_tokens":64}' >/dev/null & \
	done; wait; echo "50 requests sent - check Grafana at http://localhost:30300"

down:
	kind delete cluster --name llm-d-local

reset: down up
