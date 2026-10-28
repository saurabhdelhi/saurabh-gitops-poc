# Multi-Cluster Architecture & Management with Argo CD

## What is Multi-Cluster Argo CD?

In modern cloud-native enterprises, running a **Hub-and-Spoke** architecture is the industry standard:
- **Hub (Management Cluster)**: Runs the Argo CD control plane, Dex SSO, and GitOps operators.
- **Spokes (Workload Clusters)**: Multiple production, staging, or regional clusters (e.g., `us-east-1-prod`, `eu-central-1-prod`, `staging`) where actual customer-facing workloads run.

Argo CD does **not** need an agent installed in every cluster. Instead, it connects directly to the Spoke Kubernetes API server using a secure ServiceAccount token and certificate.

---

## Kind Multi-Cluster Networking (Under the Hood)

When running locally with `kind`:
1. Both `kind-mgmt-cluster` and `kind-workload-cluster` are Docker containers connected to the default Docker bridge network named `kind`.
2. The control plane node of Cluster 2 has the Docker container hostname `workload-cluster-control-plane`.
3. The ArgoCD application-controller running inside `mgmt-cluster` can reach Cluster 2's API server via `https://workload-cluster-control-plane:6443`.

---

## Production / AWS EKS Architecture Comparison

When migrating this pattern to AWS EKS:

| Parameter | Local Kind POC | Production AWS EKS |
| :--- | :--- | :--- |
| **API Endpoint** | `https://workload-cluster-control-plane:6443` | `https://<EKS_ID>.gr7.<region>.eks.amazonaws.com` (Private VPC endpoint via VPC Peering or Transit Gateway) |
| **Authentication** | Long-lived ServiceAccount Token Secret | AWS IAM Roles for Service Accounts (IRSA) or IAM Authenticator token |
| **TLS Verification** | CA Certificate from Kind secret | EKS Cluster CA Certificate (`certificate-authority-data`) |
| **Network Path** | Docker bridge network | AWS Transit Gateway / VPC Peering / PrivateLink |

---

## How Declarative Cluster Secrets Work

Argo CD discovers target clusters by querying Secrets in the `argocd` namespace that have the label:
```yaml
argocd.argoproj.io/secret-type: cluster
```

### Anatomy of an Argo CD Cluster Secret:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: cluster-production-us-west-2
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  name: "production-us-west-2"
  server: "https://your-target-cluster-api-endpoint:6443"
  config: |
    {
      "bearerToken": "<service_account_token>",
      "tlsClientConfig": {
        "insecure": false,
        "caData": "<base64_cluster_ca_cert>"
      }
    }
```

---

## Targeting Clusters in Argo CD Applications

Once a cluster is registered, any Argo CD Application can deploy resources to it simply by referencing its `server` URL or its `name`:

```yaml
spec:
  destination:
    # Option 1: By Server URL
    server: "https://workload-cluster-control-plane:6443"
    # Option 2: By Name
    # name: "workload-cluster"
    namespace: production
```
