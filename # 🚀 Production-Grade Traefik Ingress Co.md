# 🚀 Production-Grade Traefik Ingress Controller Setup for K3s Cluster

## Overview

This guide outlines a **production-grade setup** for Traefik as the ingress controller in a K3s cluster.  
It implements both **public (Let’s Encrypt)** and **internal (self-signed)** SSL certificates with full automation.

You’ll be able to:
- Use **IngressRoutes** for advanced routing.
- Secure **external services** with Let's Encrypt certificates for `kagiso.me`.
- Secure **internal services** with self-signed certificates for `local.kagiso.me`.
- Manage everything automatically via **Ansible + Helm**.

---

## 🧰 Prerequisites

- A functioning **K3s cluster**
- **Helm v3** installed on your control node
- **Ansible** installed on your management host
- **kubectl** access to your cluster
- Public DNS access for `kagiso.me`
- Local DNS resolving for `*.local.kagiso.me`

---

## ⚙️ 1. Disable Default Traefik in K3s

K3s comes with a built-in Traefik installation that we’ll replace with our custom one.

```bash
sudo k3s-uninstall.sh

curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable=traefik" sh -
```

## ⚙️ 2. Deploy Traefik via Ansible
  This playbook:

  - Installs Traefik with IngressRoute CRDs.
  - Enables HTTPS redirect and Let’s Encrypt.
  - Creates self-signed certificates for internal domains.
  - Persists ACME data for automatic certificate renewal.

  Save this as:
  deploy-traefik.yml

```bash
---
- name: Deploy Traefik Ingress Controller with SSL
  hosts: localhost
  connection: local
  gather_facts: false
  vars:
    traefik_namespace: traefik
    letsencrypt_email: ktjeane@outlook.com
    domain: kagiso.me
    local_domain: local.kagiso.me
    traefik_replicas: 1
    acme_storage: /data/acme.json

  tasks:

  - name: Create Traefik namespace
    kubernetes.core.k8s:
      api_version: v1
      kind: Namespace
      name: "{{ traefik_namespace }}"
      state: present

  - name: Add Traefik Helm repository
    community.kubernetes.helm_repository:
      name: traefik
      repo_url: https://traefik.github.io/charts

  - name: Update Helm repositories
    ansible.builtin.command: helm repo update
    changed_when: false

  - name: Deploy Traefik via Helm
    community.kubernetes.helm:
      name: traefik
      chart_ref: traefik/traefik
      namespace: "{{ traefik_namespace }}"
      create_namespace: false
      values:
        replicas: "{{ traefik_replicas }}"
        entryPoints:
          web:
            address: ":80"
            http:
              redirections:
                entryPoint:
                  to: websecure
                  scheme: https
                  permanent: true
          websecure:
            address: ":443"
            tls:
              enabled: true
        additionalArguments:
          - "--providers.kubernetescrd"
          - "--certificatesresolvers.letsencrypt.acme.email={{ letsencrypt_email }}"
          - "--certificatesresolvers.letsencrypt.acme.storage={{ acme_storage }}"
          - "--certificatesresolvers.letsencrypt.acme.tlschallenge=true"
        persistence:
          enabled: true
          size: 1Gi
          storageClass: default
        ingressRoute:
          dashboard:
            enabled: true

  - name: Generate self-signed certificate for local domain
    community.general.openssl_certificate:
      path: /tmp/local_kagiso_me.crt
      privatekey_path: /tmp/local_kagiso_me.key
      common_name: "{{ local_domain }}"
      provider: selfsigned
      days: 365
      state: present

  - name: Create Kubernetes TLS secret for local domain
    kubernetes.core.k8s:
      api_version: v1
      kind: Secret
      name: local-kagiso-me-tls
      namespace: "{{ traefik_namespace }}"
      type: kubernetes.io/tls
      data:
        tls.crt: "{{ lookup('file', '/tmp/local_kagiso_me.crt') | b64encode }}"
        tls.key: "{{ lookup('file', '/tmp/local_kagiso_me.key') | b64encode }}"

  - name: Create Traefik TLSStore for self-signed local domain
    kubernetes.core.k8s:
      api_version: traefik.containo.us/v1alpha1
      kind: TLSStore
      name: internal
      namespace: "{{ traefik_namespace }}"
      definition:
        spec:
          defaultCertificate:
            secretName: local-kagiso-me-tls

---
## 🚀 3. Run the Playbook
  Execute the deployment:

```bash
      ansible-playbook deploy-traefik.yml
```
  This will:

    - Deploy Traefik via Helm.
    - Configure Let’s Encrypt (for kagiso.me).
    - Create a local self-signed certificate (for local.kagiso.me).
    - Enable automatic HTTPS redirection.

## ✅ 4. Example IngressRoutes
  ### xnal Service (Public SSL via Let’s Encrypt):
```yaml
  apiVersion: traefik.containo.us/v1alpha1
  kind: IngressRoute
  metadata:
    name: whoami-external
    namespace: default
  spec:
    entryPoints:
      - websecure
    routes:
      - match: Host(`whoami.kagiso.me`)
        kind: Rule
        services:
          - name: whoami
            port: 80
    tls:
      certResolver: letsencrypt
```

  ### rnal Service (Self-Signed SSL):
```yaml
  apiVersion: traefik.containo.us/v1alpha1
  kind: IngressRoute
  metadata:
    name: whoami-internal
    namespace: default
  spec:
    entryPoints:
      - websecure
    routes:
      - match: Host(`whoami.local.kagiso.me`)
        kind: Rule
        services:
          - name: whoami
            port: 80
    tls:
      secretName: local-kagiso-me-tls

---       
## 🎉 5. Best Practices

| Area                      | Recommendation                                                   |
| ------------------------- | ---------------------------------------------------------------- |
| **Replicas**              | Minimum of 2 for high availability                               |
| **Persistence**           | Store ACME data on persistent volumes                            |
| **Security**              | Restrict dashboard access via authentication                     |
| **Monitoring**            | Integrate Traefik metrics with Prometheus/Grafana                |
| **Internal Certificates** | Rotate self-signed certificates annually or move to a private CA |
| **DNS**                   | Ensure router or Pi-hole handles `*.local.kagiso.me` resolution  |


✅ Summary

- With this setup, your Traefik installation now supports:
- Automatic Let’s Encrypt SSL for kagiso.me
- Automatic self-signed SSL for local.kagiso.me
- Fully automated deployment via Ansible
- IngressRoutes for precise, production-grade traffic control
- This forms the foundation of a top-tier, production-ready K3s cluster — capable of securely handling both public and internal workloads.

