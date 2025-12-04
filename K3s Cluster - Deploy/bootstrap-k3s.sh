#!/bin/bash
set -euo pipefail

# ------------------------------
# Helper functions
# ------------------------------
KUBECONFIG_PATH="$HOME/.kube/config"

check_command() {
    command -v "$1" >/dev/null 2>&1 || { echo "$1 is required but not installed. Exiting."; exit 1; }
}

wait_for_pods() {
    local namespace=$1
    local timeout=${2:-180s}
    echo "Waiting for pods in namespace '$namespace' to be ready..."
    kubectl --kubeconfig="$KUBECONFIG_PATH" wait --namespace "$namespace" --for=condition=Ready pods --all --timeout="$timeout"
}

# ------------------------------
# Pre-checks
# ------------------------------
check_command kubectl
check_command helm
check_command curl

echo "=== Starting K3s bootstrap from controller ==="

# ------------------------------
# 1. Cert-Manager
# ------------------------------
echo "=== Installing cert-manager ==="
kubectl --kubeconfig="$KUBECONFIG_PATH" create namespace cert-manager --dry-run=client -o yaml | \
kubectl --kubeconfig="$KUBECONFIG_PATH" apply -f -
kubectl --kubeconfig="$KUBECONFIG_PATH" apply --validate=false -f https://github.com/cert-manager/cert-manager/releases/download/v1.19.1/cert-manager.yaml
wait_for_pods cert-manager 180s
echo "Cert-manager installed and ready."

# ------------------------------
# 2. MetalLB
# ------------------------------
echo "=== Installing MetalLB ==="
kubectl --kubeconfig="$KUBECONFIG_PATH" apply --validate=false -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml

echo "Waiting for MetalLB controller and speaker pods..."
kubectl --kubeconfig="$KUBECONFIG_PATH" wait --namespace metallb-system --for=condition=Ready pods --selector=component=controller --timeout=90s
kubectl --kubeconfig="$KUBECONFIG_PATH" wait --namespace metallb-system --for=condition=Ready pods --selector=component=speaker --timeout=120s

echo "Applying MetalLB IP pool..."
cat <<EOF | kubectl --kubeconfig="$KUBECONFIG_PATH" apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: lb-pool
  namespace: metallb-system
spec:
  addresses:
    - 10.0.10.110-10.0.10.130
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
    - lb-pool
EOF
echo "MetalLB installed and IP pool applied."

# ------------------------------
# 3. Traefik (via Helm)
# ------------------------------
echo "=== Installing Traefik via Helm ==="
helm repo add traefik https://traefik.github.io/charts
helm repo update

kubectl --kubeconfig="$KUBECONFIG_PATH" create namespace traefik --dry-run=client -o yaml | \
kubectl --kubeconfig="$KUBECONFIG_PATH" apply -f -

helm upgrade --install traefik traefik/traefik \
  -n traefik \
  -f /home/kagiso/k3s/traefik/traefik-values.yaml \
  --kubeconfig "$KUBECONFIG_PATH" \
  --wait

echo "Traefik installed and ready."

# ------------------------------
# 4. ArgoCD
# ------------------------------
echo "=== Installing ArgoCD ==="
kubectl --kubeconfig="$KUBECONFIG_PATH" create namespace argocd --dry-run=client -o yaml | \
kubectl --kubeconfig="$KUBECONFIG_PATH" apply -f -
kubectl --kubeconfig="$KUBECONFIG_PATH" apply --validate=false -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

wait_for_pods argocd 180s
echo "ArgoCD installed and ready."

echo "=== K3s bootstrap completed successfully from controller! ==="
