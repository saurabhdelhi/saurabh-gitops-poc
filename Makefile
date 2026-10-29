.PHONY: help clusters-up clusters-down install-argocd register-cluster get-password port-forward-argocd deploy-apps status lab-pause lab-resume

SHELL := /usr/bin/env bash
export PATH := /opt/homebrew/bin:/usr/local/bin:$(PATH)

help:
	@echo "=========================================================================="
	@echo " Senior DevOps Hands-On Lab: Multi-Cluster ArgoCD + Google SAML POC"
	@echo "=========================================================================="
	@echo "  make clusters-up          - Provision both Kind clusters (mgmt + workload)"
	@echo "  make install-argocd       - Deploy ArgoCD via Helm on the mgmt cluster"
	@echo "  make register-cluster     - Securely register workload cluster into ArgoCD"
	@echo "  make get-password         - Retrieve ArgoCD initial admin password"
	@echo "  make port-forward-argocd  - Port-forward ArgoCD server UI to localhost:8080"
	@echo "  make deploy-apps          - Deploy App-of-Apps across both clusters"
	@echo "  make status               - Check status of nodes, pods, and clusters"
	@echo "  make lab-pause            - Pause clusters & free RAM/CPU (preserves state)"
	@echo "  make lab-resume           - Resume clusters when you are back"
	@echo "  make clusters-down        - Destroy both Kind clusters"
	@echo "=========================================================================="

clusters-up:
	@echo ">> Creating Cluster 1 (Management Cluster)..."
	kind create cluster --name mgmt-cluster --config clusters/kind-mgmt-cluster.yaml
	@echo ">> Creating Cluster 2 (Workload Cluster)..."
	kind create cluster --name workload-cluster --config clusters/kind-workload-cluster.yaml
	@echo ">> Both clusters are UP and running!"

install-argocd:
	@echo ">> Switching context to kind-mgmt-cluster..."
	kubectl config use-context kind-mgmt-cluster
	@echo ">> Adding Argo Helm repository..."
	helm repo add argo https://argoproj.github.io/argo-helm
	helm repo update
	@echo ">> Installing ArgoCD using production Helm values..."
	helm upgrade --install argocd argo/argo-cd \
		--namespace argocd \
		--create-namespace \
		-f argocd-infra/helm/values-production.yaml
	@echo ">> Waiting for ArgoCD server deployment to become ready..."
	kubectl -n argocd rollout status deployment/argocd-server --timeout=180s
	@echo ">> ArgoCD is successfully installed!"

register-cluster:
	@echo ">> Registering workload-cluster into ArgoCD..."
	chmod +x multi-cluster/register-workload-cluster.sh
	./multi-cluster/register-workload-cluster.sh

get-password:
	@echo ">> Retrieving ArgoCD initial admin password:"
	@kubectl --context kind-mgmt-cluster -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode; echo ""

port-forward-argocd:
	@echo ">> Port-forwarding ArgoCD UI on http://localhost:8085 (Username: admin)"
	kubectl --context kind-mgmt-cluster -n argocd port-forward svc/argocd-server 8085:80

deploy-apps:
	@echo ">> Applying Root GitOps Application..."
	kubectl --context kind-mgmt-cluster apply -f gitops-apps/root-bootstrap.yaml

status:
	@echo "--- [Management Cluster Nodes] ---"
	@kubectl --context kind-mgmt-cluster get nodes
	@echo "--- [Management Cluster ArgoCD Pods] ---"
	@kubectl --context kind-mgmt-cluster -n argocd get pods
	@echo "--- [Workload Cluster Nodes] ---"
	@kubectl --context kind-workload-cluster get nodes
	@echo "--- [Workload Cluster Namespaces] ---"
	@kubectl --context kind-workload-cluster get ns

lab-pause:
	@echo ">> Pausing both Kind clusters (stopping Docker containers)..."
	@docker stop $$(docker ps -q --filter "name=mgmt-cluster" --filter "name=workload-cluster")
	@echo ">> Lab paused! CPU & RAM freed. All state and data are preserved."

lab-resume:
	@echo ">> Resuming both Kind clusters (starting Docker containers)..."
	@docker start $$(docker ps -a -q --filter "name=mgmt-cluster" --filter "name=workload-cluster")
	@echo ">> Waiting 15s for Kubernetes control planes to be ready..."
	@sleep 15
	@kubectl --context kind-mgmt-cluster get nodes
	@kubectl --context kind-workload-cluster get nodes
	@echo ">> Clusters are back online! Run 'make port-forward-argocd' to reopen the UI."

clusters-down:
	@echo ">> Deleting kind-mgmt-cluster..."
	kind delete cluster --name mgmt-cluster || true
	@echo ">> Deleting kind-workload-cluster..."
	kind delete cluster --name workload-cluster || true
	@echo ">> Cleaned up all lab clusters!"
