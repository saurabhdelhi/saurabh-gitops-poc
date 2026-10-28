# 2-Cluster Production-Style ArgoCD Architecture

## Topology Overview

```
                      ┌──────────────────────────────────────────────┐
                      │            Google Workspace IdP              │
                      │  (SAML 2.0 Auth + Group Membership Claims)   │
                      └──────────────────────┬───────────────────────┘
                                             │ SAML Assertion
                                             ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│  Cluster 1: Management / Control Plane Cluster (`mgmt-cluster`)                         │
│                                                                                        │
│   ┌────────────────────────────────────────────────────────────────────────────────┐   │
│   │ ArgoCD Installation (via Official Helm Chart)                                  │   │
│   │                                                                                │   │
│   │  • argocd-server (UI & API)                                                    │   │
│   │  • argocd-dex-server (SAML Connector to Google Workspace)                      │   │
│   │  • argocd-repo-server (Manifest Generation / Helm Renderer)                    │   │
│   │  • argocd-application-controller (Reconciliation loop)                        │   │
│   │  • argocd-redis-ha / redis (State & Cache)                                     │   │
│   │  • argocd-cm & argocd-rbac-cm (Dex SAML + Role-Based Access Control)          │   │
│   └──────────────────────┬──────────────────────────────┬──────────────────────────┘   │
│                          │                              │                              │
│                          ▼ (in-cluster target)          ▼ (remote target via Secret)   │
│   ┌──────────────────────────────┐                      │                              │
│   │ Local Deployments            │                      │                              │
│   │ (e.g., Shared Observability, │                      │                              │
│   │  Core Ingress, Mgmt Tools)   │                      │                              │
│   └──────────────────────────────┘                      │                              │
└─────────────────────────────────────────────────────────┼──────────────────────────────┘
                                                          │ Kube-API over TLS
                                                          │ (Cross-cluster ServiceAccount)
                                                          ▼
┌────────────────────────────────────────────────────────────────────────────────────────┐
│  Cluster 2: Target Workload Cluster (`workload-cluster`)                               │
│                                                                                        │
│   ┌────────────────────────────────────────────────────────────────────────────────┐   │
│   │ Dedicated ServiceAccount (`argocd-manager`) with ClusterRole & Token Secret    │   │
│   └────────────────────────────────────────────────────────────────────────────────┘   │
│                          │                                                             │
│                          ▼ (Deployed by ArgoCD Controller from Mgmt Cluster)           │
│   ┌────────────────────────────────────────────────────────────────────────────────┐   │
│   │ Production Microservices (Helm-packaged)                                       │   │
│   │  • Deployments, Services, Ingress, HPAs, PodDisruptionBudgets                  │   │
│   │  • Namespaces: `production`, `staging`                                         │   │
│   └────────────────────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Key Components & Senior DevOps Concepts

| Component | Role | Senior DevOps Focus |
| :--- | :--- | :--- |
| **Kind Clusters** | Simulates 2 distinct K8s clusters locally | Control plane isolation, worker nodes, inter-cluster networking. |
| **ArgoCD Helm Chart** | Manages ArgoCD lifecycle declaratively | Treating the GitOps tool itself as code; upgrading via values rather than raw kubectl manifests. |
| **Multi-Cluster Registration** | Connects `workload-cluster` to `mgmt-cluster` | Principle of least privilege for the `argocd-manager` ServiceAccount, TLS verification, secret rotation. |
| **Google SAML 2.0 (Dex)** | Enterprise Single Sign-On | Group attribute extraction, identity federation, seamless user offboarding through Google Workspace. |
| **ArgoCD RBAC (`argocd-rbac-cm`)** | Fine-grained authorization | Mapping Google Groups (`devops-core`, `app-devs`) to ArgoCD roles (`admin`, `read-only`, `sync-only`). |
| **App-of-Apps Pattern** | Declarative GitOps deployment | Single root application that tracks and reconciles child Helm applications across both clusters. |
