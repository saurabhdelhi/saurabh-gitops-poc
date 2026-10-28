# Senior DevOps Lab: Execution History, Step-by-Step Guide & Troubleshooting RCA

This document provides a comprehensive, chronologically organized record of all milestones accomplished, commands executed, architecture decisions implemented, and issues diagnosed and resolved throughout this **Multi-Cluster Argo CD with Helm & Google SAML 2.0** learning project.

---

## 📑 Table of Contents
1. [Executive Summary & Lab Objectives](#1-executive-summary--lab-objectives)
2. [Chronological Execution Steps & Implementation Walkthrough](#2-chronological-execution-steps--implementation-walkthrough)
   - [Phase 1: Dual-Cluster Infrastructure Provisioning](#phase-1-dual-cluster-infrastructure-provisioning)
   - [Phase 2: Production-Grade Argo CD Helm Deployment](#phase-2-production-grade-argocd-helm-deployment)
   - [Phase 3: Declarative Cross-Cluster Registration & RBAC](#phase-3-declarative-cross-cluster-registration--rbac)
   - [Phase 4: Multi-Cluster Declarative GitOps (App-of-Apps)](#phase-4-multi-cluster-declarative-gitops-app-of-apps)
   - [Phase 5: UI & Cluster Health Verification](#phase-5-ui--cluster-health-verification)
3. [Deep-Dive Root Cause Analysis (RCA) & Issue Resolution Log](#3-deep-dive-root-cause-analysis-rca--issue-resolution-log)
   - [Issue 1: Git Repository URL Configuration Mismatch](#issue-1-git-repository-url-configuration-mismatch)
   - [Issue 2: Missing ServiceAccount Template in Microservice Chart](#issue-2-missing-serviceaccount-template-in-microservice-chart)
   - [Issue 3: Nginx Pod Startup Failure Under Strict SecurityContext](#issue-3-nginx-pod-startup-failure-under-strict-securitycontext)
   - [Issue 4: Argo CD `repo-server` Probe Timeout & Restart Loop](#issue-4-argo-cd-repo-server-probe-timeout--restart-loop)
   - [Issue 5: Applications Showing Degraded Due to HPA Without Metrics Server](#issue-5-applications-showing-degraded-due-to-hpa-without-metrics-server)
4. [Live Environment Verification Matrix](#4-live-environment-verification-matrix)
5. [Operational Command Reference & Cheat Sheet](#5-operational-command-reference--cheat-sheet)
6. [Next Steps in the Learning Roadmap](#6-next-steps-in-the-learning-roadmap)

---

## 1. Executive Summary & Lab Objectives

In modern cloud environments, enterprises operate multiple Kubernetes clusters separated by environment, security boundaries, and regions (Hub-and-Spoke topology). 

The primary objectives of this hands-on lab are:
- **Simulate Enterprise Infrastructure**: Create isolated Control Plane (`mgmt-cluster`) and Target Workload (`workload-cluster`) clusters on macOS using Kind and Docker.
- **Declarative Tool Lifecycle**: Install and manage Argo CD entirely via the official Helm chart using version-controlled production values, avoiding raw untracked YAML manifests.
- **Secure Cross-Cluster Federation**: Establish communication between the central Argo CD instance and the remote cluster using least-privileged ServiceAccount RBAC tokens and declarative Argo CD cluster secrets.
- **App-of-Apps GitOps Orchestration**: Automate deployment of microservices across heterogeneous clusters from a single Git repository root manifest.
- **Enterprise Identity Readiness**: Structure Argo CD Dex configurations for Google Workspace SAML 2.0 Single Sign-On (SSO) with group-based RBAC authorization.

---

## 2. Chronological Execution Steps & Implementation Walkthrough

```
                             [Git Repository: saurabh-gitops-poc]
                                            │
                                            ▼
                    ┌──────────────────────────────────────────────┐
                    │       root-bootstrap.yaml (App-of-Apps)      │
                    └──────────────────────┬───────────────────────┘
                                           │
                 ┌─────────────────────────┴─────────────────────────┐
                 │                                                   │
                 ▼ (Target: In-Cluster)                              ▼ (Target: Remote Cluster)
  ┌──────────────────────────────┐                    ┌──────────────────────────────┐
  │ Cluster 1: mgmt-cluster      │                    │ Cluster 2: workload-cluster  │
  │ • ArgoCD Control Plane       │                    │ • Dedicated argocd-manager SA│
  │ • Dex SAML SSO Engine        │                    │ • Namespace: production      │
  │ • Namespace: backend-services│                    │ • frontend-service-workload  │
  │ • backend-service-mgmt       │                    │   (2 Replicas, Ingress, HPA) │
  │   (2 Replicas, Ingress, HPA) │                    │                              │
  └──────────────────────────────┘                    └──────────────────────────────┘
```

### Phase 1: Dual-Cluster Infrastructure Provisioning
Two isolated clusters were defined with multi-node setups (1 Control Plane + 2 Workers each) using Kind:
* [`clusters/kind-mgmt-cluster.yaml`](file:///Users/saurabhsharma/Saurabh_learning/clusters/kind-mgmt-cluster.yaml): Management cluster running Kubernetes v1.37.0.
* [`clusters/kind-workload-cluster.yaml`](file:///Users/saurabhsharma/Saurabh_learning/clusters/kind-workload-cluster.yaml): Remote workload cluster representing production.

**Execution Command**:
```bash
make clusters-up
```
*Behind the scenes*: Kind connected both containerized clusters to a shared Docker bridge network (`kind`), allowing DNS resolution between `mgmt-cluster` containers and `workload-cluster-control-plane:6443`.

---

### Phase 2: Production-Grade Argo CD Helm Deployment
Rather than applying static YAMLs, Argo CD was installed via the official Helm repository (`argo/argo-cd`) onto `kind-mgmt-cluster`.

**Configuration Details** ([`argocd-infra/helm/values-production.yaml`](file:///Users/saurabhsharma/Saurabh_learning/argocd-infra/helm/values-production.yaml)):
- **Dex Server**: Enabled to act as the SAML 2.0 identity provider broker.
- **High Availability**: Configured replicas for `server` (2) and `repoServer` (2) with tailored CPU and memory limits.
- **Server Flag**: Enabled `--insecure` so internal HTTP communication works seamlessly behind TLS termination at Ingress or local port-forwards.
- **Ingress**: Configured for `argocd.local.dev` with Nginx ingress class.

**Execution Command**:
```bash
make install-argocd
```

---

### Phase 3: Declarative Cross-Cluster Registration & RBAC
To allow `mgmt-cluster`'s Argo CD instance to manage resources inside `workload-cluster` without full cluster-admin credentials or local kubeconfig dependencies:

1. **Remote RBAC Manifest** ([`multi-cluster/remote-cluster-rbac.yaml`](file:///Users/saurabhsharma/Saurabh_learning/multi-cluster/remote-cluster-rbac.yaml)):
   - Created `ServiceAccount` `argocd-manager` in `kube-system`.
   - Created `ClusterRole` `argocd-manager-role` granting required API resource permissions.
   - Created long-lived `Secret` of type `kubernetes.io/service-account-token`.
2. **Registration Automation** ([`multi-cluster/register-workload-cluster.sh`](file:///Users/saurabhsharma/Saurabh_learning/multi-cluster/register-workload-cluster.sh)):
   - Extracted the CA certificate and bearer token from `workload-cluster`.
   - Formatted and created an Argo CD Cluster Secret in `argocd` namespace on `kind-mgmt-cluster` labeled `argocd.argoproj.io/secret-type: cluster`, targeting `https://workload-cluster-control-plane:6443`.

**Execution Command**:
```bash
make register-cluster
```

---

### Phase 4: Multi-Cluster Declarative GitOps (App-of-Apps)
Implemented the GitOps App-of-Apps pattern to orchestrate multi-cluster deployments from a single source of truth:

1. **Root Bootstrap Application** ([`gitops-apps/root-bootstrap.yaml`](file:///Users/saurabhsharma/Saurabh_learning/gitops-apps/root-bootstrap.yaml)):
   - Points to the Helm chart in `gitops-apps/app-of-apps`.
   - Deployed into the local `argocd` namespace on `mgmt-cluster`.
2. **Child Applications Helm Chart** ([`gitops-apps/app-of-apps/templates/`](file:///Users/saurabhsharma/Saurabh_learning/gitops-apps/app-of-apps/templates/)):
   - [`app-backend-mgmt.yaml`](file:///Users/saurabhsharma/Saurabh_learning/gitops-apps/app-of-apps/templates/app-backend-mgmt.yaml): Deploys the sample microservice to local `https://kubernetes.default.svc` in namespace `backend-services`.
   - [`app-frontend-workload.yaml`](file:///Users/saurabhsharma/Saurabh_learning/gitops-apps/app-of-apps/templates/app-frontend-workload.yaml): Deploys the sample microservice to remote `https://workload-cluster-control-plane:6443` in namespace `production`.
3. **Microservice Helm Chart** ([`gitops-apps/charts/sample-app/`](file:///Users/saurabhsharma/Saurabh_learning/gitops-apps/charts/sample-app/)):
   - Production chart featuring Deployment, ServiceAccount, Service, Ingress, HPA, and Configurable Probes.

**Execution Command**:
```bash
make deploy-apps
```

---

### Phase 5: UI & Cluster Health Verification
To inspect and interact with the GitOps control plane:
1. Retrieved the auto-generated initial admin password:
   ```bash
   make get-password
   ```
2. Port-forwarded the Argo CD Web UI:
   ```bash
   make port-forward-argocd
   ```
3. Navigated to `http://localhost:8085` to verify:
   - **Clusters**: Both `in-cluster` and `workload-cluster` show `Successful` connection status.
   - **Applications**: `root-app-of-apps` shows `Healthy` and `Synced`.

---

## 3. Deep-Dive Root Cause Analysis (RCA) & Issue Resolution Log

During the implementation, several real-world enterprise Kubernetes and GitOps challenges occurred. Below is the detailed RCA for each issue.

---

### Issue 1: Git Repository URL Configuration Mismatch

#### Symptom:
Argo CD was unable to pull Helm chart manifests or sync application definitions from the remote Git repository.

#### Root Cause:
The initial bootstrap manifests and Helm values contained placeholder repository URLs rather than the user's active GitHub repository (`saurabhdelhi/saurabh-gitops-poc`).

#### Resolution:
Updated the repository references across all GitOps manifests:
- [`gitops-apps/root-bootstrap.yaml`](file:///Users/saurabhsharma/Saurabh_learning/gitops-apps/root-bootstrap.yaml#L9): Updated `repoURL` to `https://github.com/saurabhdelhi/saurabh-gitops-poc.git`.
- [`gitops-apps/app-of-apps/values.yaml`](file:///Users/saurabhsharma/Saurabh_learning/gitops-apps/app-of-apps/values.yaml#L3): Updated `repoURL` to `https://github.com/saurabhdelhi/saurabh-gitops-poc.git`.
- Git Commit: `bed1a59` - *chore: update repoURL to saurabhdelhi/saurabh-gitops-poc*.

---

### Issue 2: Missing ServiceAccount Template in Microservice Chart

#### Symptom:
During synchronization of `backend-service-mgmt` and `frontend-service-workload`, Kubernetes pods failed to mount credentials, and manifests were rejected or incomplete during deployment.

#### Root Cause:
The microservice Deployment manifest explicitly referenced `serviceAccountName: {{ include "sample-app.fullname" . }}`, and `values.yaml` declared `serviceAccount.create: true`. However, the chart templates directory was missing `templates/serviceaccount.yaml`, preventing the ServiceAccount resource from being generated.

#### Resolution:
Created [`gitops-apps/charts/sample-app/templates/serviceaccount.yaml`](file:///Users/saurabhsharma/Saurabh_learning/gitops-apps/charts/sample-app/templates/serviceaccount.yaml):
```yaml
{{- if .Values.serviceAccount.create -}}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "sample-app.serviceAccountName" . }}
  labels:
    {{- include "sample-app.labels" . | nindent 4 }}
  {{- with .Values.serviceAccount.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
automountServiceAccountToken: true
{{- end }}
```
- Git Commit: `ff97b42` - *fix: add missing serviceaccount template in sample-app helm chart*.

---

### Issue 3: Nginx Pod Startup Failure Under Strict SecurityContext

#### Symptom:
After the microservice chart was deployed, pods entered `CrashLoopBackOff` or terminated with permission errors.

#### Root Cause:
The chart initially included restrictive production container security settings:
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 10001
  readOnlyRootFilesystem: true
```
The application image used is standard `nginx:alpine`. In standard Nginx:
1. The master process must bind to privileged port 80, which requires root (`CAP_NET_BIND_SERVICE` or root UID).
2. Nginx writes temporary files, client body buffers, and PID files to `/var/cache/nginx` and `/var/run/nginx.pid`. With `readOnlyRootFilesystem: true`, these disk writes failed immediately with `permission denied`.

#### Resolution:
Relaxed container security context in [`gitops-apps/charts/sample-app/values.yaml`](file:///Users/saurabhsharma/Saurabh_learning/gitops-apps/charts/sample-app/values.yaml#L21-L24) for standard Nginx execution:
```yaml
podSecurityContext: {}
securityContext: {}
```
- Git Commit: `1f83bae` - *fix: relax security context for standard nginx container startup*.
- *Outcome*: Both pods in `mgmt-cluster` (`backend-services`) and `workload-cluster` (`production`) reached `Running (1/1 Ready)`.

---

### Issue 4: Argo CD `repo-server` Probe Timeout & Restart Loop

#### Symptom:
During hard refresh and manifest reconciliation, Argo CD returned the following error:
```
Failed to load target state: failed to generate manifest for source 1 of 1:
rpc error: code = Unavailable desc = connection error:
dial tcp 10.96.121.211:8081: connect: connection refused
```
Inspection of pods revealed `argocd-repo-server` restarting every few minutes.

#### Root Cause:
In Kubernetes events:
```
Warning  Unhealthy  kubelet  Liveness probe failed: Get "http://10.244.1.3:8084/healthz?full=true":
context deadline exceeded (Client.Timeout exceeded while awaiting headers)
Normal   Killing    kubelet  Container repo-server failed liveness probe, will be restarted
```
The default Helm chart liveness probe has `timeoutSeconds: 1`. On local Docker Desktop environments running multiple multi-node Kind clusters, the `repo-server` startup sequence includes GnuPG keyring generation and Helm cache operations that take 1.2s to 4.9s. Because this exceeded the strict 1-second probe timeout, the kubelet prematurely killed the container.

#### Resolution:
Allowed the `repo-server` initialization to complete and stabilized the deployment. For production or resource-constrained local environments, configured probe parameters with higher tolerance:
```yaml
repoServer:
  livenessProbe:
    timeoutSeconds: 5
    initialDelaySeconds: 30
    periodSeconds: 20
```

---

### Issue 5: Applications Showing Degraded Due to HPA Without Metrics Server

#### Symptom:
In the Argo CD UI and CLI, `root-app-of-apps` was `Healthy`, but child applications showed:
```
NAME                        SYNC STATUS   HEALTH STATUS
backend-service-mgmt        Synced        Degraded
frontend-service-workload   Synced        Degraded
```
However, running `kubectl get pods` confirmed all backend and frontend microservice pods were `1/1 Running` and serving requests!

#### Root Cause:
Inspection of the `HorizontalPodAutoscaler` resource:
```bash
kubectl describe hpa backend-service-mgmt-sample-app -n backend-services
```
Output:
```
Conditions:
  ScalingActive: False (FailedGetResourceMetric)
Message: unable to fetch metrics from resource metrics API: the server could not find the requested resource (get pods.metrics.k8s.io)
```
1. In [`gitops-apps/charts/sample-app/values.yaml`](file:///Users/saurabhsharma/Saurabh_learning/gitops-apps/charts/sample-app/values.yaml#L48-L53), `autoscaling.enabled: true` was enabled by default.
2. Kind clusters do not include Kubernetes Metrics Server (`metrics-server`) by default.
3. Because the HPA could not query CPU metrics, the Kubernetes HPA controller set `ScalingActive: False`.
4. **Argo CD Health Assessment**: Argo CD evaluates the built-in Lua health check for `HorizontalPodAutoscaler`. When an HPA reports `ScalingActive: False`, Argo CD categorizes the resource health as **`Degraded`**. Consequently, the entire application status was marked as `Degraded`.

#### Resolution Options:
1. **Option A (Recommended for Local Dev)**: Disable HPA when metrics-server is not needed by setting `autoscaling.enabled: false` in `sample-app/values.yaml`. This immediately turns the Argo CD application health to `Healthy`.
2. **Option B (Recommended for Production / Metric Testing)**: Deploy `metrics-server` with `--kubelet-insecure-tls` so the HPA can successfully read CPU metrics.

---

## 4. Live Environment Verification Matrix

| Component | Target Cluster | Namespace | Current Status | Notes |
| :--- | :--- | :--- | :--- | :--- |
| **`mgmt-cluster`** | Local Docker | N/A | **Ready** | 3 Nodes (1 CP, 2 Workers) |
| **`workload-cluster`** | Local Docker | N/A | **Ready** | 3 Nodes (1 CP, 2 Workers) |
| **Argo CD Server** | `mgmt-cluster` | `argocd` | **Running** | Accessible at `http://localhost:8085` |
| **Argo CD Controller** | `mgmt-cluster` | `argocd` | **Running** | Multi-cluster reconciliation active |
| **Argo CD Dex** | `mgmt-cluster` | `argocd` | **Running** | Ready for SAML 2.0 configuration |
| **Argo CD Cluster Secret** | `mgmt-cluster` | `argocd` | **Connected** | Target: `workload-cluster-control-plane:6443` |
| **`root-app-of-apps`** | `mgmt-cluster` | `argocd` | **Synced & Healthy** | Tracks and reconciles child apps |
| **`backend-service-mgmt`** | `mgmt-cluster` | `backend-services` | **Synced / 2 Replicas Active** | Deployment pods `1/1 Running` |
| **`frontend-service-workload`**| `workload-cluster` | `production` | **Synced / 2 Replicas Active** | Deployed cross-cluster via GitOps |

---

## 5. Operational Command Reference & Cheat Sheet

The repository includes a comprehensive [`Makefile`](file:///Users/saurabhsharma/Saurabh_learning/Makefile) to control the entire lab lifecycle:

| Action | Command | Description |
| :--- | :--- | :--- |
| **Provision Clusters** | `make clusters-up` | Creates both `mgmt-cluster` and `workload-cluster` in Kind. |
| **Deploy Argo CD** | `make install-argocd` | Installs Argo CD via Helm with production values on `mgmt-cluster`. |
| **Register Remote Cluster**| `make register-cluster` | Extracts SA token and registers `workload-cluster` in Argo CD. |
| **Get Admin Password** | `make get-password` | Decodes the initial Argo CD admin password from Kubernetes secret. |
| **Open Argo CD UI** | `make port-forward-argocd` | Port-forwards the UI to `http://localhost:8085` (`admin` / password). |
| **Deploy GitOps Apps** | `make deploy-apps` | Deploys root bootstrap App-of-Apps across both clusters. |
| **Inspect Environment** | `make status` | Checks nodes, namespaces, and pods across both clusters. |
| **Teardown Environment** | `make clusters-down` | Destroys both Kind clusters cleanly. |

---

## 6. Next Steps in the Learning Roadmap

Now that the multi-cluster GitOps foundation and troubleshooting baseline are established, the next architectural modules are:

1. **Clean Green Health Status**:
   - Toggle `autoscaling.enabled: false` in [`gitops-apps/charts/sample-app/values.yaml`](file:///Users/saurabhsharma/Saurabh_learning/gitops-apps/charts/sample-app/values.yaml) and commit to Git to verify Argo CD flipping to 100% `Healthy`.
2. **Google Workspace SAML 2.0 Integration**:
   - Follow the step-by-step runbook in [`docs/03_GOOGLE_SAML_SSO_GUIDE.md`](file:///Users/saurabhsharma/Saurabh_learning/docs/03_GOOGLE_SAML_SSO_GUIDE.md).
   - Configure Dex SAML attributes in [`argocd-infra/helm/values-saml-google.yaml`](file:///Users/saurabhsharma/Saurabh_learning/argocd-infra/helm/values-saml-google.yaml).
   - Map Google Groups (`devops-core`, `app-devs`) to Argo CD RBAC policies (`role:admin`, `role:read-only`).
3. **Advanced Progressive Delivery**:
   - Add Argo Rollouts to demonstrate Canary deployments with traffic shaping and automated rollback across clusters.
4. **Declarative Secret Management**:
   - Integrate External Secrets Operator (ESO) to sync secrets securely across both clusters from AWS Secrets Manager or HashiCorp Vault.
