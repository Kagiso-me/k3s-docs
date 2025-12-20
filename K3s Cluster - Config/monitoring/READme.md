<div align="center">

# 📊 Kubernetes Monitoring Stack (k3s)
### Prometheus • Grafana • Alertmanager  
**GitOps-first | Production-grade | Persistent**

![Kubernetes](https://img.shields.io/badge/Kubernetes-k3s-326ce5?style=for-the-badge&logo=kubernetes&logoColor=white)
![Prometheus](https://img.shields.io/badge/Prometheus-Metrics-e6522c?style=for-the-badge&logo=prometheus&logoColor=white)
![Grafana](https://img.shields.io/badge/Grafana-Dashboards-f46800?style=for-the-badge&logo=grafana&logoColor=white)
![ArgoCD](https://img.shields.io/badge/GitOps-ArgoCD-fb2c36?style=for-the-badge&logo=argo&logoColor=white)
![Helm](https://img.shields.io/badge/Helm-Charts-0f1689?style=for-the-badge&logo=helm&logoColor=white)

</div>

---

## 📌 Overview

This repository defines a **complete Kubernetes monitoring stack** for **k3s clusters**, deployed using:

- **Prometheus Operator**
- **Grafana**
- **Alertmanager**
- **Helm**
- **ArgoCD (GitOps)**

Designed for:
- Homelabs
- Edge clusters
- Production-adjacent environments
- Engineers who care about correctness and durability

---

## 🧠 Why We Deploy Monitoring

> _“If you can’t measure it, you can’t trust it.”_

Monitoring is **not optional infrastructure**.

This stack enables us to:

✅ Detect node and pod failures early  
✅ Track CPU, memory, disk, and network usage  
✅ Observe pod restarts and crash loops  
✅ Monitor persistent storage growth  
✅ Debug incidents with evidence, not guesswork  
✅ Upgrade and scale with confidence  

Without monitoring:
- Failures are silent
- Capacity planning is reactive
- Automation becomes risky

This repository makes **observability a first-class citizen**.

---

## 🏗️ How We Deploy Monitoring

### Design Principles

| Principle | Why it matters |
|---------|---------------|
| Kubernetes-native | Uses ServiceMonitors & PodMonitors |
| GitOps-first | Declarative, auditable, reproducible |
| Persistent | Metrics survive restarts & upgrades |
| k3s-aware | No broken control-plane scrapes |
| Minimal but extensible | Easy to grow, hard to break |

---

## 🧩 Architecture

```mermaid
flowchart TD
    subgraph GitHub
        A[Monitoring Repo<br/>README + Values]
    end

    subgraph ArgoCD
        B[ArgoCD Application]
    end

    subgraph k3s Cluster
        subgraph monitoring namespace
            C[Prometheus]
            D[Grafana]
            E[Alertmanager]
            F[kube-state-metrics]
            G[node-exporter]
        end
    end

    A --> B
    B --> C
    B --> D
    B --> E
    C --> F
    C --> G
