# K3s Cluster Support (Automated Bootstrap)

This repository provides a fully automated setup for a **K3s cluster** with:

- [MetalLB](https://metallb.universe.tf/)
- [Cert-Manager](https://cert-manager.io/)
- [Traefik](https://doc.traefik.io/traefik/) with custom values

The workflow uses `kubectl` and `helm` for deployment.

---

## Prerequisites

- K3s cluster running
- `kubectl` configured
- `helm` installed (v3+)
- Optional: Ansible for playbook automation

---

## 1. Bootstrap Script (Automated)

You can bootstrap the cluster by running:

```bash
./bootstrap.sh
```

---
`bootstrap.sh`

```bash
#!/bin/bash
set -e

echo "=== Installing MetalLB ==="
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.15.2/config/manifests/metallb-native.yaml

cat <<EOF | kubectl apply -f -
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
EOF

echo "=== Installing Cert-Manager ==="
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.18.0/cert-manager.yaml

echo "=== Deploying Traefik with custom values ==="
helm repo add traefik https://traefik.github.io/charts
helm repo update

# Ensure traefik-values.yaml exists in the same directory
helm upgrade --install traefik traefik/traefik \
  --namespace traefik \
  --create-namespace \
  --values traefik-values.yaml

echo "=== Bootstrap complete! ==="
kubectl get pods -n traefik

```
---

## 2. Traefik Custom Values

Save the following as traefik-values.yaml in the same folder as bootstrap.sh:

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

## 3. Post-Installation

Check the status of your deployments:

```bash
kubectl get pods -n traefik
kubectl get svc -n traefik
kubectl get ingressclass
```

- Traefik Dashboard is disabled by default.
- Services are exposed via MetalLB IP pool (10.0.10.100-150) or Traefik LoadBalancer IP (10.0.10.110).

---

## 4. Notes & Best Practices
- Maintain Traefik and Cert-Manager versions compatible with K3s
- Monitor logs for SSL/TLS or routing errors
- Avoid overlapping MetalLB IP pool with DHCP/static IP ranges
- For high availability, Traefik replicas ≥ 3
- Customize traefik-values.yaml per environment needs


---

This setup provides a production-ready bare-metal K3s environment with dynamic load balancing, TLS certificates, and a fully configurable Traefik ingress controller.
