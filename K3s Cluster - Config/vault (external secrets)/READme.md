# Vault Integration in K3s Cluster

This document describes how to integrate HashiCorp Vault into a K3s cluster to improve security, manage secrets, use dynamic credentials, enable PKI/TLS, provide auditing, and synchronize secrets into Kubernetes. It also includes example manifests for common apps like Nextcloud, MariaDB, and Redis using Vault-injected or synced secrets.

---

## Table of Contents

* [Overview](#overview)
* [Secret Management](#secret-management)

  * [Kubernetes Secrets vs Vault](#kubernetes-secrets-vs-vault)
  * [Vault Agent Injector](#vault-agent-injector)
  * [Vault-to-Kubernetes Secret Sync](#vault-to-kubernetes-secret-sync)
  * [Pros & Cons](#secret-management-pros--cons)
* [Dynamic Secrets](#dynamic-secrets)

  * [Database Credentials Example](#database-credentials-example)
  * [Pros & Cons](#dynamic-secrets-pros--cons)
* [Kubernetes Authentication](#kubernetes-authentication)
* [PKI & TLS Management](#pki--tls-management)
* [Auditing](#auditing)
* [Recommended Implementation](#recommended-implementation)
* [Architecture Diagram](#architecture-diagram)
* [Example Deployments](#example-deployments)

---

## Overview

Vault provides a centralized, encrypted, and policy-driven system for managing secrets, certificates, and credentials.
It improves K3s security by:

* Encrypting secrets at rest
* Controlling access with fine-grained policies
* Supporting dynamic secret generation
* Integrating with Kubernetes authentication
* Enabling PKI/TLS management and auditing
* Synchronizing secrets into Kubernetes for standard usage

---

## Secret Management

### Kubernetes Secrets vs Vault

| Feature             | Kubernetes Secrets | Vault                    |
| ------------------- | ------------------ | ------------------------ |
| Encryption at rest  | Base64 only        | AES-256 by default       |
| Rotation            | Manual             | Automatic/Programmatic   |
| Fine-grained access | Namespace-level    | Policies per pod/service |
| Audit logging       | Minimal            | Extensive                |

Vault provides stronger security and auditing than Kubernetes secrets.

---

### Vault Agent Injector

Vault Agent Injector automatically injects secrets into pods at runtime.

**Steps to implement:**

1. Enable KV secrets engine:

```bash
vault secrets enable -path=kv kv-v2
vault kv put kv/database username='dbuser' password='supersecret'
```

2. Deploy Vault Agent Injector as a DaemonSet in the cluster.

3. Annotate pods for secret injection:

```yaml
metadata:
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/role: "k3s-app"
    vault.hashicorp.com/agent-inject-secret-db: "kv/data/database"
```

### Vault-to-Kubernetes Secret Sync

Vault can synchronize secrets into Kubernetes Secrets using operators like:

* External Secrets Operator (ESO)
* Kubernetes External Secrets (KES)
* Vault Secrets Operator (official)

This method creates native Kubernetes Secrets that apps can consume without sidecars.

Example ESO CRD:

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

Secrets automatically update if Vault changes.

### Secret Management Pros & Cons

**Pros:**

* Injector: Secrets never touch etcd, injected at runtime
* Sync: Works with all apps, appears as native Kubernetes Secrets
* Both methods support dynamic secret rotation

**Cons:**

* Injector: Slight pod startup overhead, requires DaemonSet
* Sync: Secrets exist in Kubernetes memory/etcd, slightly less secure, operator needs Vault read access

---

## Dynamic Secrets

Vault can generate temporary credentials for databases, cloud services, or APIs.

### Database Credentials Example

```bash
vault secrets enable database

vault write database/config/mydb \
    plugin_name=mysql-database-plugin \
    connection_url="{{username}}:{{password}}@tcp(mysql:3306)/" \
    username="root" \
    password="rootpassword"

vault write database/roles/myapp \
    db_name=mydb \
    creation_statements="CREATE USER '{{name}}'@'%' IDENTIFIED BY '{{password}}'; GRANT ALL ON mydb.* TO '{{name}}'@'%';" \
    default_ttl="1h" \
    max_ttl="24h"
```

Pods request credentials dynamically, which expire automatically.

### Dynamic Secrets Pros & Cons

**Pros:**

* Minimizes blast radius if a pod is compromised
* Automatic expiration and rotation
* No hardcoded secrets

**Cons:**

* Adds complexity
* Requires Vault connectivity at runtime

---

## Kubernetes Authentication

Pods can authenticate to Vault using their ServiceAccount tokens:

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

Each pod can only access secrets allowed by its Vault policy.

---

## PKI & TLS Management

Vault can act as a certificate authority (CA) for internal TLS:

* Issue short-lived TLS certificates
* Enable encrypted pod-to-pod communication
* Automate certificate renewal

**Pros:**

* Eliminates manual certificate management
* Reduces attack surface for compromised nodes

**Cons:**

* Requires setup and operational overhead
* Requires secure Vault PKI backend storage

---

## Auditing

Vault provides audit logging:

```bash
vault audit enable file file_path=/var/log/vault_audit.log
```

* Tracks every read/write operation
* Useful for compliance and forensic investigation

---

## Recommended Implementation for Your Setup

For your K3s cluster running multiple services and dynamic workloads:

* **Primary method:** Vault Agent Injector (keeps secrets out of etcd, ideal for dynamic DB creds, API keys)
* **Optional method:** Vault-to-Kubernetes Secret Sync for apps that require native Kubernetes Secrets and cannot handle injection

This balances security and usability.

---

## Architecture Diagram

```
           +----------------+
           |     Vault      |
           | (Secrets, PKI) |
           +--------+-------+
                    |
           +--------v-------+
           | Vault Agent DS |
           | (DaemonSet)    |
           +--------+-------+
                    |
      +-------------+-------------+
      |                           |
+-----v-----+               +-----v-----+
| App Pod 1 |               | App Pod 2 |
| (Injected)|               | (Injected)|
+-----------+               +-----------+

Optional: Vault sync operator updates K8s Secrets for apps without injection.
```

---

## Example Deployments

(Example manifests remain the same as before, supporting both injection and sync)

### Nextcloud Deployment with Vault Secrets

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: nextcloud-sa
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nextcloud
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nextcloud
  template:
    metadata:
      labels:
        app: nextcloud
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "k3s-app"
        vault.hashicorp.com/agent-inject-secret-db: "kv/data/database"
    spec:
      serviceAccountName: nextcloud-sa
      containers:
      - name: nextcloud
        image: nextcloud:latest
        env:
        - name: DB_USER
          valueFrom:
            secretKeyRef:
              name: vault-secret-db
              key: username
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: vault-secret-db
              key: password
        ports:
        - containerPort: 80
```

(Other manifests for MariaDB and Redis remain unchanged)


 ┌─────────────────────┐
 │   Kubernetes Pod    │
 │  (App: Nextcloud,   │
 │   MariaDB, Redis,   │
 │   PostgreSQL client)│
 │                     │
 │  ServiceAccount     │
 │  token mounted      │
 └─────────┬───────────┘
           │
           │ 1️⃣ Pod requests secret via ExternalSecrets
           ▼
 ┌─────────────────────┐
 │ ExternalSecrets     │
 │ Operator (ESO)      │
 │ in K3s cluster      │
 └─────────┬───────────┘
           │
           │ 2️⃣ ESO authenticates to Vault using
           │    ClusterSecretStore (token)
           ▼
 ┌─────────────────────┐
 │ Vault Server        │
 │ (running on RPi)    │
 │                     │
 │ DB plugin configured│
 │ for PostgreSQL      │
 └─────────┬───────────┘
           │
           │ 3️⃣ Vault connects to PostgreSQL
           │    via external IP (MetalLB LoadBalancer)
           ▼
 ┌─────────────────────┐
 │ PostgreSQL Service  │
 │ (K3s cluster)       │
 └─────────────────────┘
