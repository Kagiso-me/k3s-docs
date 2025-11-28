# K3s Cluster Support

This repository documents the setup and support configuration for a **K3s cluster** including:

- [MetalLB](https://metallb.universe.tf/)
- [Cert-Manager](https://cert-manager.io/)
- [Traefik (custom configuration)](https://doc.traefik.io/traefik/)

---

## Prerequisites

- A running K3s cluster
- `kubectl` configured to access the cluster
- Optional: Ansible for automated deployments (custom playbooks)

---

## 1. MetalLB

MetalLB provides LoadBalancer support in bare-metal K3s clusters.

### Installation

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.2/config/manifests/metallb-native.yaml
```
### Configuration

```bash
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default
  namespace: metallb-system
spec:
  addresses:
  - 10.0.10.110-10.0.10.130
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
spec: {}

```
---

## 2. Cert-Manager
Cert-Manager automatically provisions TLS certificates for Ingress resources.

MetalLB provides LoadBalancer support in bare-metal K3s clusters.

### Installation

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.19.1/cert-manager.yaml
```
### Notes:
- Ensure your cluster can reach the ACME server if using Let's Encrypt
- Custom issuers can be defined per environment

---

## 3. Traefik (Custom Values)
Traefik is configured with custom values extracted from an Ansible playbook.

### Helm Deployment

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm upgrade --install traefik traefik/traefik \
  --namespace traefik \
  --create-namespace \
  --values traefik-values.yaml
```

`traefik-values.yaml`
```bash
globalArguments:
  - "--global.sendanonymoususage=false"
  - "--global.checknewversion=false"

additionalArguments:
  - "--serversTransport.insecureSkipVerify=true"
  - "--log.level=INFO"

deployment:
  enabled: true
  replicas: 3

ports:
  web:
    redirections:
      entrypoint:
        to: websecure
        priority: 10
  websecure:
    http3:
      enabled: true
    advertisedPort: 443
    tls:
      enabled: true

ingressRoute:
  dashboard:
    enabled: false

providers:
  kubernetesCRD:
    enabled: true
    ingressClass: traefik
    allowExternalNameServices: true
  kubernetesIngress:
    enabled: true
    allowExternalNameServices: true
    publishedService:
      enabled: false

rbac:
  enabled: true

service:
  enabled: true
  type: LoadBalancer
  spec:
    loadBalancerIP: 10.0.10.110

loadBalancerSourceRanges: []
externalIPs: []

```
---

## 4. Accessing Services

Once deployed:

- Traefik Dashboard: Disabled by default (IngressRoute.dashboard.enabled: false)
- Your services will be exposed on the LoadBalancer IPs defined in MetalLB or Traefik

---

## 5. Notes & Best Practices

- Keep Traefik updated with the latest stable Helm chart
- Always monitor Traefik logs for SSL/TLS issues
- MetalLB IP pools should not overlap with DHCP/static IP ranges
- For HA clusters, ensure Traefik replicas >= 3




