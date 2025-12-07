# Vault-to-Kubernetes Secret Sync Cheat Sheet

This cheat sheet shows how to sync secrets from HashiCorp Vault to Kubernetes using the External Secrets Operator (ESO). Apps can consume secrets as native Kubernetes Secrets, with automatic updates.

---

## 1️⃣ Prerequisites

* Vault running and reachable from the cluster
* KV secrets engine enabled and secrets stored:

```bash
vault secrets enable -path=kv kv-v2
vault kv put kv/database username='dbuser' password='supersecret'
```

* Vault token with read access for the operator, stored as a Kubernetes Secret:

```bash
kubectl create secret generic vault-token --from-literal=token='<VAULT_TOKEN>'
```

* External Secrets Operator installed:

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace \
  --set installCRDs=true

```

---

## 2️⃣ Define the Vault Backend (ClusterSecretStore)

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: vault-backend
spec:
  vault:
    server: "https://vault.kagiso.me:8200"
    path: "kv/data"
    auth:
      token:
        secretRef:
          name: vault-token
          key: token
```

* `server` → Vault URL
* `path` → Vault KV engine path
* `secretRef` → Kubernetes Secret storing the Vault token

---

## 3️⃣ Define an ExternalSecret

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: my-db-secret
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: my-db-secret
    creationPolicy: Owner
  data:
    - secretKey: username
      remoteRef:
        key: kv/data/database
        property: username
    - secretKey: password
      remoteRef:
        key: kv/data/database
        property: password
```

Secrets are automatically synced from Vault to the Kubernetes Secret `my-db-secret`.

---

## 4️⃣ Use the Secret in a Pod

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: demo-app
  template:
    metadata:
      labels:
        app: demo-app
    spec:
      containers:
      - name: demo-app
        image: alpine:latest
        command: ["/bin/sh", "-c"]
        args:
          - echo "DB_USER=$DB_USER, DB_PASSWORD=$DB_PASSWORD" && sleep infinity
        env:
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: my-db-secret
              key: username
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: my-db-secret
              key: password
```

* Pod consumes the secret **as a normal Kubernetes Secret**. No Vault Agent or sidecar is needed.

---

## 5️⃣ Quick Test

```bash
kubectl exec -it <demo-app-pod> -- env | grep DB_
```

Expected output:

```
DB_USER=dbuser
DB_PASSWORD=supersecret
```

---

## 6️⃣ Tips

* Dynamic secrets can also be synced; ESO will refresh them automatically.
* Operator should have Vault read access only (least privilege).
* Sync multiple secrets into different K8s Secrets for various apps.
* `refreshInterval` controls how often secrets are updated — set according to security policy.

---

**Summary:** Vault-to-Kubernetes Secret Sync is simple, secure, and allows apps to consume secrets as native Kubernetes Secrets, with automatic updates and rotation.
