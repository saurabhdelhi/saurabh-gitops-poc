#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Script: register-workload-cluster.sh
# Purpose: Registers the remote Workload Cluster into the ArgoCD Management Cluster
# ==============================================================================

MGMT_CTX="kind-mgmt-cluster"
WORKLOAD_CTX="kind-workload-cluster"
TARGET_CLUSTER_NAME="workload-cluster"

echo "=== [1/4] Applying RBAC to Workload Cluster ($WORKLOAD_CTX) ==="
kubectl --context "$WORKLOAD_CTX" apply -f multi-cluster/remote-cluster-rbac.yaml

echo "Waiting for ServiceAccount token secret to be populated..."
sleep 3

echo "=== [2/4] Extracting Credentials from Workload Cluster ==="
SA_TOKEN=$(kubectl --context "$WORKLOAD_CTX" -n argocd get secret argocd-manager-token -o jsonpath='{.data.token}' | base64 --decode)
CA_DATA=$(kubectl --context "$WORKLOAD_CTX" -n argocd get secret argocd-manager-token -o jsonpath='{.data.ca\.crt}')

# When running in Kind, the management pods reach the workload cluster via Docker's internal DNS
# For Kind: https://workload-cluster-control-plane:6443
# For Cloud / AWS EKS: Replace with https://<eks-cluster-endpoint>
CLUSTER_ENDPOINT="https://workload-cluster-control-plane:6443"

echo "=== [3/4] Registering Cluster Secret in Management Cluster ($MGMT_CTX) ==="
cat <<EOF | kubectl --context "$MGMT_CTX" apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: cluster-${TARGET_CLUSTER_NAME}
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  name: "${TARGET_CLUSTER_NAME}"
  server: "${CLUSTER_ENDPOINT}"
  config: |
    {
      "bearerToken": "${SA_TOKEN}",
      "tlsClientConfig": {
        "insecure": false,
        "caData": "${CA_DATA}"
      }
    }
EOF

echo "=== [4/4] Verifying Registered Clusters in ArgoCD ==="
kubectl --context "$MGMT_CTX" -n argocd get secrets -l argocd.argoproj.io/secret-type=cluster
echo ""
echo "✅ Workload cluster '${TARGET_CLUSTER_NAME}' successfully registered into ArgoCD!"
