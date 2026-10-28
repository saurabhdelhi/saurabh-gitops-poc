# Senior DevOps Lab: Multi-Cluster Argo CD with Helm & Google SAML 2.0

Welcome to your hands-on production POC! This repository is designed to simulate a real-world enterprise infrastructure environment where you manage **multiple Kubernetes clusters** using **Argo CD installed via Helm**, declarative **GitOps App-of-Apps**, and **Google Workspace SAML 2.0 Single Sign-On (SSO)**.

---

## 📁 Repository Structure

```
.
├── Makefile                                # Automated 1-click lab commands
├── clusters/
│   ├── kind-mgmt-cluster.yaml              # Cluster 1: ArgoCD Control Plane (HA)
│   └── kind-workload-cluster.yaml          # Cluster 2: Remote Target Cluster (Production)
├── argocd-infra/
│   └── helm/
│       ├── values-production.yaml          # Production ArgoCD Helm values (HA, Dex, limits)
│       └── values-saml-google.yaml         # Google Workspace SAML 2.0 SSO + RBAC mapping
├── multi-cluster/
│   ├── remote-cluster-rbac.yaml            # ServiceAccount, ClusterRole & Token on remote cluster
│   └── register-workload-cluster.sh        # Automates declarative cross-cluster registration
├── gitops-apps/
│   ├── root-bootstrap.yaml                 # Root App-of-Apps manifest
│   ├── app-of-apps/                        # App-of-Apps Chart (deploys across clusters)
│   │   ├── Chart.yaml
│   │   ├── values.yaml
│   │   └── templates/
│   │       ├── app-backend-mgmt.yaml       # Targets Management Cluster
│   │       └── app-frontend-workload.yaml  # Targets Remote Workload Cluster
│   └── charts/
│       └── sample-app/                     # Production microservice Helm chart
└── docs/
    ├── 01_ARCHITECTURE.md                  # Topology diagram and concept breakdown
    ├── 02_MULTI_CLUSTER_SETUP.md           # How cross-cluster networking and secrets work
    ├── 03_GOOGLE_SAML_SSO_GUIDE.md         # Full Google Workspace Admin Console setup guide
    └── 04_EXECUTION_HISTORY_AND_TROUBLESHOOTING.md # Full execution log, steps, & troubleshooting RCA
```

---

## 🚀 Quick Start (Hands-On Lab)

### Prerequisites
Make sure you have installed on your Mac:
- **Docker Desktop** (running)
- **kubectl** (`brew install kubectl`)
- **kind** (`brew install kind`)
- **helm** (`brew install helm`)

---

### Step 1: Provision Both Clusters
Spin up `mgmt-cluster` (Cluster 1) and `workload-cluster` (Cluster 2):
```bash
make clusters-up
```

Verify both clusters exist:
```bash
kind get clusters
# Output:
# mgmt-cluster
# workload-cluster
```

---

### Step 2: Install Argo CD via Official Helm Chart
Deploys Argo CD with production values onto `mgmt-cluster`:
```bash
make install-argocd
```

---

### Step 3: Register the Remote Workload Cluster
Extracts ServiceAccount credentials from `workload-cluster` and registers the cluster into Argo CD declaratively:
```bash
make register-cluster
```

---

### Step 4: Access Argo CD UI
1. Retrieve the initial admin password:
   ```bash
   make get-password
   ```
2. Open the UI via port-forward:
   ```bash
   make port-forward-argocd
   ```
3. Visit **[http://localhost:8085](http://localhost:8085)** in your browser.
   - **Username**: `admin`
   - **Password**: *(output from `make get-password`)*

Go to **Settings** > **Clusters** in the Argo CD UI: You will see **both clusters** connected with `Successful` connection status:
1. `in-cluster` (`https://kubernetes.default.svc`)
2. `workload-cluster` (`https://workload-cluster-control-plane:6443`)

---

### Step 5: Test Multi-Cluster App Deployment
Deploy the App-of-Apps which deploys one service to the local management cluster and another service to the remote workload cluster:
```bash
make deploy-apps
```

Check the pods running inside the remote workload cluster:
```bash
kubectl --context kind-workload-cluster -n production get pods
```

---

## 🔐 Google Workspace SAML 2.0 POC

For the SAML authentication requirement:
1. Read the complete runbook in [docs/03_GOOGLE_SAML_SSO_GUIDE.md](file:///Users/saurabhsharma/Saurabh_learning/docs/03_GOOGLE_SAML_SSO_GUIDE.md).
2. It guides you through configuring the Google Admin Console (ACS URL, Entity ID, Name ID, and **Group attribute mapping**).
3. Update [argocd-infra/helm/values-saml-google.yaml](file:///Users/saurabhsharma/Saurabh_learning/argocd-infra/helm/values-saml-google.yaml) with your Google SSO URL and base64 certificate.
4. Upgrade ArgoCD:
   ```bash
   helm upgrade --install argocd argo/argo-cd \
     -n argocd \
     -f argocd-infra/helm/values-production.yaml \
     -f argocd-infra/helm/values-saml-google.yaml
   ```

---

## 🧹 Teardown Lab
When you are done testing, cleanly delete both clusters:
```bash
make clusters-down
```
