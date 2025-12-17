# 🔐 Authentik – Identity & Access Layer for the Homelab

## What is Authentik?

**Authentik** is a modern, self-hosted **identity provider (IdP)** that adds authentication, authorization, and identity management to your applications.

Think of Authentik as the **front door security guard** for your apps:
- CrowdSec decides **who should be blocked** (bad actors)
- Authentik decides **who is allowed in** (real users)

It operates at **Layer 7 (application layer)** and integrates cleanly with reverse proxies like **Traefik**.

---

## Why Authentik is Needed

CrowdSec is excellent at stopping:
- Brute-force attacks
- Scanners & bots
- Malicious IPs

However, CrowdSec **does not authenticate users**.

Authentik fills this gap by providing:
- 🔑 Single Sign-On (SSO)
- 🔐 Multi-Factor Authentication (MFA)
- 👤 Centralized user management
- 🧠 Application-level access control

### Together, they form Defense in Depth

| Layer | Tool | Purpose |
|-----|------|--------|
| L3/L4 | CrowdSec | Block malicious traffic |
| L7 | Authentik | Authenticate & authorize users |
| Routing | Traefik | TLS termination & routing |

---

## How Authentik Fits Into This Architecture

```
Internet
   │
Edge Pi (CrowdSec Bouncer)
   │ clean traffic only
Traefik Ingress
   │
Authentik Middleware
   │
Protected App (Nextcloud / Immich / WordPress)
```

- Authentik sits **behind Traefik**
- It is enforced using **Traefik ForwardAuth middleware**
- Unauthenticated users are redirected to Authentik login
- Authenticated users are forwarded to the app

---

# 🚀 Deploying Authentik in Kubernetes (Step-by-Step)

This guide assumes:
- Kubernetes is already running
- Traefik is your Ingress Controller
- Helm is installed
- You control DNS for your domain

---

## 1️⃣ Prerequisites

### Required DNS Records

Create the following DNS entries:

```
auth.yourdomain.com  -> Traefik LoadBalancer IP
app.yourdomain.com   -> Traefik LoadBalancer IP
```

### Required Namespaces

```bash
kubectl create namespace authentik
```

---

## 2️⃣ Add the Authentik Helm Repository

```bash
helm repo add authentik https://charts.goauthentik.io
helm repo update
```

---

## 3️⃣ Generate Secrets (IMPORTANT)

Generate a strong secret key:

```bash
openssl rand -base64 50
```

Create a secret file:

```yaml
# authentik-secrets.yaml
apiVersion: v1
kind: Secret
metadata:
  name: authentik-secret
  namespace: authentik
type: Opaque
data:
  AUTHENTIK_SECRET_KEY: <BASE64_ENCODED_SECRET>
```

Apply it:

```bash
kubectl apply -f authentik-secrets.yaml
```

---

## 4️⃣ Authentik Helm Values (Recommended & Stable)

```yaml
# values.yaml

authentik:
  secret_key: env:AUTHENTIK_SECRET_KEY

server:
  ingress:
    enabled: true
    ingressClassName: traefik
    hosts:
      - host: auth.yourdomain.com
        paths:
          - /
    tls:
      - secretName: authentik-tls
        hosts:
          - auth.yourdomain.com

postgresql:
  enabled: true
  auth:
    username: authentik
    password: strongpassword
    database: authentik

redis:
  enabled: true

worker:
  replicas: 1
```

### Why These Values Matter

- Built-in PostgreSQL & Redis ensure **easy, reliable startup**
- Ingress is Traefik-native
- TLS is handled by Traefik + cert-manager
- Minimal replicas = homelab friendly

---

## 5️⃣ Install Authentik

```bash
helm install authentik authentik/authentik \
  --namespace authentik \
  -f values.yaml
```

Wait for pods:

```bash
kubectl get pods -n authentik
```

---

## 6️⃣ Initial Setup

Visit:

```
https://auth.yourdomain.com/if/flow/initial-setup/
```

Create:
- Admin user
- Admin password

---

## 7️⃣ Create a ForwardAuth Provider

1. Admin → Applications → Providers
2. Create **Proxy Provider**
3. Mode: **Forward Auth (Traefik)**
4. External Host:

```
https://auth.yourdomain.com
```

Save the provider.

---

## 8️⃣ Create an Application

1. Applications → Create
2. Name: Protected App
3. Provider: ForwardAuth provider
4. Policy Engine: default

---

## 9️⃣ Traefik Middleware Configuration

Create middleware:

```yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: authentik-forwardauth
  namespace: authentik
spec:
  forwardAuth:
    address: https://auth.yourdomain.com/outpost.goauthentik.io/auth/traefik
    trustForwardHeader: true
    authResponseHeaders:
      - X-authentik-username
      - X-authentik-groups
      - X-authentik-email
```

Apply it:

```bash
kubectl apply -f authentik-middleware.yaml
```

---

## 🔗 Protecting an App with Authentik

Add middleware to your Ingress:

```yaml
traefik.ingress.kubernetes.io/router.middlewares: authentik-authentik-forwardauth@kubernetescrd
```

Now:
- Unauthenticated users → redirected to Authentik
- Authenticated users → allowed through

---

## ✅ Final Result

- CrowdSec blocks attackers at the edge
- Authentik enforces identity & MFA
- Traefik routes only trusted traffic
- Apps remain fast and stable

---

> **CrowdSec asks:** "Is this traffic malicious?"
> **Authentik asks:** "Is this user allowed?"

Together, they secure your homelab the right way.
