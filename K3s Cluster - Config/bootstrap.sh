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
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.19.1/cert-manager.yaml

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
