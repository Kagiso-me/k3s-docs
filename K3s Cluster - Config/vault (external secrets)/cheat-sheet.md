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

## Dynamic Secrets

Vault can generate temporary credentials for databases, cloud services, or APIs.


### Dynamic PostgreSQL Secret Example

```bash
vault secrets enable database

vault write database/config/pg \
    plugin_name=postgresql-database-plugin \
    allowed_roles="pg-app" \
    connection_url="postgresql://{{username}}:{{password}}@postgres:5432/postgres?sslmode=disable" \
    username="postgres" \
    password="postgrespassword"

vault write database/roles/pg-app \
    db_name=pg \
    creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT ALL PRIVILEGES ON DATABASE postgres TO \"{{name}}\";" \
    default_ttl="30m" \
    max_ttl="1h"
```
**ExternalSecret example to sync dynamic PostgreSQL creds:**

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: pg-credentials
spec:
  refreshInterval: 5m
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: pg-credentials
    creationPolicy: Owner
  data:
    - secretKey: username
      remoteRef:
        key: database/creds/pg-app
        property: username
    - secretKey: password
      remoteRef:
        key: database/creds/pg-app
        property: password
```
### PostgreSQL Deployment (dynamic credentials)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
      - name: postgres
        image: postgres:latest
        env:
        - name: POSTGRES_USER
          valueFrom:
            secretKeyRef:
              name: pg-credentials
              key: username
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: pg-credentials
              key: password
```

* ESO will fetch new credentials as Vault rotates them.
* Mount as a file or env vars in your pod to consume updated credentials.

### Dynamic Secrets Pros & Cons

**Pros:**

* Minimizes blast radius if a pod is compromised
* Automatic expiration and rotation
* No hardcoded secrets

**Cons:**

* Requires operator sync interval to match TTL for short-lived secrets
* Environment variable updates require pod restart or reload mechanism

---

## Kubernetes Authentication

Pods authenticate to Vault using ServiceAccount tokens:

```bash
vault auth enable kubernetes

vault write auth/kubernetes/config \
    token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
    kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

vault write auth/kubernetes/role/k3s-app \
    bound_service_account_names=app-sa \
    bound_service_account_namespaces=default \
    policies=myapp-policy \
    ttl=1h
```


## 6️⃣ Tips

* Dynamic secrets can also be synced; ESO will refresh them automatically.
* Operator should have Vault read access only (least privilege).
* Sync multiple secrets into different K8s Secrets for various apps.
* `refreshInterval` controls how often secrets are updated — set according to security policy.

---

**Summary:** Vault-to-Kubernetes Secret Sync is simple, secure, and allows apps to consume secrets as native Kubernetes Secrets, with automatic updates and rotation.
