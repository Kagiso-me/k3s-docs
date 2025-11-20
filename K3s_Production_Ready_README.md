**Production-grade K3s cluster build guide**, designed for **Ansible-based automation** and **kubectl-based management thereafter**.

---

````markdown
# 🧩 K3s Production-Ready Cluster — Automated with Ansible

> _“Infrastructure that feels like magic — but is actually just well-written YAML.”_

This README documents how to **automate your K3s cluster setup using Ansible**, followed by a complete checklist to make your homelab **secure, scalable, and production-ready**.

Once your cluster is up (by the end of **Phase 3**), you’ll handle all operations and add-ons from your control host (`RPi`) using `kubectl`.

---
## ⚙️ Cluster Topology

| Role   | Hostname | IP Address  | Specs                     |
|---------|-----------|-------------|----------------------------|
| Server / Master | `tywin` | 10.0.10.5 | Intel NUC (i3-5010U, 12 GB RAM) |
| Worker | `jaime` | 10.0.10.4 | Lenovo ThinkCentre (i5-4570T, 16 GB RAM) |
| Worker | `tyrion` | 10.0.10.3 | Lenovo ThinkCentre (i5-4570T, 16 GB RAM) |
| Control / Ansible host / kubectl | `rpi` | 10.0.10.2 | Raspberry Pi 3B+ |

---

## 🧭 Phase 1 — Preparing Nodes with Ansible

### 🔑 Why this phase matters
Before we can let Ansible do its thing, every node needs to be ready for remote orchestration.  
Ansible communicates over SSH and executes Python code on the target — **so we must ensure SSH and Python are ready**.

---

### 🪪 Inventory file (inventory.ini)

```ini
[master]
tywin ansible_host=10.0.10.5 ansible_user=kagiso

[workers]
jaime ansible_host=10.0.10.4 ansible_user=kagiso
tyrion ansible_host=10.0.10.3 ansible_user=kagiso

[all:vars]
ansible_python_interpreter=/usr/bin/python3
````

---

### 🧰 Base playbook — node prep and security hardening

Save as `prepare-nodes.yml`:

```yaml
---
- name: Prepare all nodes for K3s installation
  hosts: all
  become: yes
  tasks:
    - name: Update apt cache and upgrade packages
      ansible.builtin.apt:
        update_cache: yes
        upgrade: dist

    - name: Ensure Python is installed
      ansible.builtin.apt:
        name: [python3, python3-apt]
        state: present
      tags: python
      # 🔍 Explanation:
      # Ansible executes its modules via Python on the remote host.
      # Without this, the agent can’t interpret commands — so it’s mandatory for all targets.

    - name: Disable swap
      ansible.builtin.command: swapoff -a
      when: ansible_swaptotal_mb > 0

    - name: Remove swap entries from fstab
      ansible.builtin.replace:
        path: /etc/fstab
        regexp: '^\s*[^#].*swap'
        replace: ''
      notify: Reload systemd

    - name: Kernel sysctl settings for Kubernetes
      ansible.builtin.copy:
        dest: /etc/sysctl.d/99-kubernetes.conf
        content: |
          net.ipv4.ip_forward=1
          net.bridge.bridge-nf-call-iptables=1
          net.bridge.bridge-nf-call-ip6tables=1
          vm.swappiness=0
      notify: Apply sysctl

    - name: Ensure chrony is installed and enabled for time sync
      ansible.builtin.apt:
        name: chrony
        state: present
      notify: Enable chrony

  handlers:
    - name: Apply sysctl
      ansible.builtin.command: sysctl --system
    - name: Reload systemd
      ansible.builtin.systemd:
        daemon_reload: yes
    - name: Enable chrony
      ansible.builtin.systemd:
        name: chrony
        enabled: yes
        state: started
```

Run it:

```bash
ansible-playbook -i inventory.ini prepare-nodes.yml
```

---

## 🏗️ Phase 2 — Installing K3s with Ansible

Now that your nodes are prepped, let’s install K3s using a playbook so you don’t touch any node manually.

### Playbook: `install-k3s.yml`

```yaml
---
- name: Install K3s on master
  hosts: master
  become: yes
  tasks:
    - name: Install K3s server
      ansible.builtin.shell: |
        curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
          --tls-san 10.0.10.5 \
          --disable traefik \
          --disable servicelb \
          --disable local-storage \
          --write-kubeconfig-mode 644" sh -s -
      args:
        creates: /usr/local/bin/k3s

    - name: Retrieve node token
      ansible.builtin.command: cat /var/lib/rancher/k3s/server/node-token
      register: k3s_token
      changed_when: false
      run_once: true

    - name: Save token for workers
      delegate_to: localhost
      ansible.builtin.copy:
        dest: ./k3s_token.txt
        content: "{{ k3s_token.stdout }}"

- name: Install K3s on workers
  hosts: workers
  become: yes
  tasks:
    - name: Read master token
      ansible.builtin.slurp:
        src: ./k3s_token.txt
      register: token_file
      delegate_to: localhost

    - name: Install K3s agent
      ansible.builtin.shell: |
        curl -sfL https://get.k3s.io | K3S_URL=https://10.0.10.5:6443 \
        K3S_TOKEN={{ token_file['content'] | b64decode }} sh -
      args:
        creates: /usr/local/bin/k3s-agent


####################################################################
# 1️⃣ - Configure Kubeconfig on Ansible control host (for Helm)
####################################################################
- name: Retrieve kubeconfig from master
  hosts: master
  become: yes
  tasks:
    - name: Fetch kubeconfig
      ansible.builtin.fetch:
        src: /etc/rancher/k3s/k3s.yaml
        dest: ./kubeconfig
        flat: yes

- name: Prepare kubeconfig for local Helm/Kubectl use
  hosts: localhost
  tasks:
    - name: Replace localhost with master IP
      ansible.builtin.replace:
        path: ./kubeconfig
        regexp: '127\.0\.0\.1'
        replace: '10.0.10.5'


####################################################################
# 2️⃣ - Install MetalLB
####################################################################
- name: Deploy MetalLB
  hosts: master
  become: false
  tasks:
    - name: Add MetalLB Helm repo
      ansible.builtin.shell: helm repo add metallb https://metallb.github.io/metallb && helm repo update

    - name: Install MetalLB via Helm
      ansible.builtin.shell: |
        helm upgrade --install metallb metallb/metallb \
          --namespace metallb-system --create-namespace
      environment:
        KUBECONFIG: ./kubeconfig

    - name: Configure MetalLB address pool
      ansible.builtin.copy:
        dest: ./metallb-config.yaml
        content: |
          apiVersion: metallb.io/v1beta1
          kind: IPAddressPool
          metadata:
            name: default-address-pool
            namespace: metallb-system
          spec:
            addresses:
              - 10.0.10.20-10.0.10.29
          ---
          apiVersion: metallb.io/v1beta1
          kind: L2Advertisement
          metadata:
            name: l2adv
            namespace: metallb-system
      delegate_to: localhost

    - name: Apply MetalLB address pool config
      ansible.builtin.shell: kubectl apply -f ./metallb-config.yaml
      environment:
        KUBECONFIG: ./kubeconfig


####################################################################
# 3️⃣ - Install Cert-Manager
####################################################################
- name: Deploy Cert-Manager
  hosts: master
  become: false
  tasks:
    - name: Add Jetstack Helm repo
      ansible.builtin.shell: helm repo add jetstack https://charts.jetstack.io && helm repo update

    - name: Install Cert-Manager
      ansible.builtin.shell: |
        helm upgrade --install cert-manager jetstack/cert-manager \
          --namespace cert-manager --create-namespace \
          --set installCRDs=true
      environment:
        KUBECONFIG: ./kubeconfig


####################################################################
# 4️⃣ - Install Longhorn (storage)
####################################################################
- name: Deploy Longhorn
  hosts: master
  become: false
  tasks:
    - name: Add Longhorn Helm repo
      ansible.builtin.shell: helm repo add longhorn https://charts.longhorn.io && helm repo update

    - name: Install Longhorn
      ansible.builtin.shell: |
        helm upgrade --install longhorn longhorn/longhorn \
          --namespace longhorn-system --create-namespace
      environment:
        KUBECONFIG: ./kubeconfig


####################################################################
# 5️⃣ - Install Traefik (custom values)
####################################################################
- name: Deploy Traefik with custom values
  hosts: master
  become: false
  tasks:
    - name: Add Traefik Helm repo
      ansible.builtin.shell: helm repo add traefik https://traefik.github.io/charts && helm repo update

    - name: Copy Traefik values file
      ansible.builtin.copy:
        dest: ./traefik-values.yaml
        content: |
          globalArguments:
            - "--global.sendanonymoususage=false"
            - "--global.checknewversion=false"
          additionalArguments:
            - "--serversTransport.insecureSkipVerify=true"
            - "--log.level=INFO"
          deployment:
            enabled: true
            replicas: 1
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
              ingressClass: traefik-external
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
              loadBalancerIP: 10.0.10.20
          loadBalancerSourceRanges: []
          externalIPs: []

    - name: Install Traefik via Helm
      ansible.builtin.shell: |
        helm upgrade --install traefik traefik/traefik \
          --namespace kube-system \
          -f ./traefik-values.yaml
      environment:
        KUBECONFIG: ./kubeconfig


Run it:

```bash
ansible-playbook -i inventory.ini install-k3s.yml
```

---

## 🧩 Phase 3 — Verify and Label Cluster

After installation, you can now manage the cluster from your control host (`RPi`).

### Get kubeconfig

```bash
scp kagiso@10.0.10.5:/etc/rancher/k3s/k3s.yaml ~/kubeconfig
sed -i 's/127.0.0.1/10.0.10.5/' ~/kubeconfig
export KUBECONFIG=~/kubeconfig
```

### Verify nodes

```bash
kubectl get nodes -o wide
```

### Label & taint

```bash
kubectl label node tywin role=master
kubectl label node jaime role=worker
kubectl label node tyrion role=worker
kubectl taint nodes tywin node-role.kubernetes.io/master=:NoSchedule
```

✅ This ensures workloads only run on your workers by default, keeping the control plane clean.

---

## 🌐 Phase 4 — Networking & DNS

Now that your cluster is alive, networking is handled by **Flannel (default)**.
We’re keeping this simple and reliable — VXLAN overlay just works for homelab setups.

You can optionally add **ExternalDNS** to automate DNS record creation if you use Cloudflare, Route53, etc.

Example (Cloudflare):

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install external-dns bitnami/external-dns \
  --set provider=cloudflare \
  --set cloudflare.apiToken=$CF_API_TOKEN \
  -n kube-system
```

---

## 🚪 Phase 5 — Ingress & TLS (Traefik + cert-manager)

Traefik routes external traffic into the cluster, while cert-manager automates your TLS certificates.

### Install cert-manager

```bash
kubectl create namespace cert-manager
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager --namespace cert-manager --set installCRDs=true
```

### Install Traefik via Helm

```bash
helm repo add traefik https://traefik.github.io/charts
helm install traefik traefik/traefik -n traefik --create-namespace -f - <<EOF
additionalArguments:
  - "--providers.kubernetesingress"
  - "--api.insecure=false"
service:
  type: NodePort
EOF
```

---

## 💾 Phase 6 — Persistent Storage (Longhorn)

Longhorn gives you distributed, resilient storage.

```bash
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.4.3/deploy/longhorn.yaml
```

Access the Longhorn UI through NodePort or Ingress, and set your backup target (NFS/S3).

---

## 📊 Phase 7 — Monitoring & Logging

### Prometheus + Grafana

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install kube-prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace
```

### Loki + Promtail

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm install loki grafana/loki-stack -n logging --create-namespace
```

---

## 🔐 Phase 8 — Authentication (Authelia)

Add SSO and MFA to your dashboards and services via Authelia.
You’ll integrate it with Traefik middleware for access control.

```bash
helm repo add authelia https://charts.authelia.io
helm install authelia authelia/authelia -n authelia --create-namespace -f authelia-values.yaml
```

---

## 💾 Phase 9 — Backups & DR

### Etcd snapshots

```bash
sudo k3s etcd-snapshot save --name pre-upgrade
sudo k3s etcd-snapshot ls
```

### K8up backups

```bash
helm repo add k8up https://charts.k8up.io
helm install k8up k8up/k8up -n k8up --create-namespace
```

---

## 📣 Phase 10 — Alerts & Notifications

Alertmanager (from Prometheus) can notify via Slack, Teams, or webhook.

Example Slack config:

```yaml
receivers:
- name: 'slack'
  slack_configs:
  - api_url: 'https://hooks.slack.com/services/TOKEN'
    channel: '#alerts'
```

---

## 🧹 Phase 11 — Maintenance & Best Practices

* Regularly **snapshot etcd** before upgrades.
* Use **namespaces** for clear separation.
* Apply **resource limits** and **PodDisruptionBudgets**.
* Secure secrets with **Sealed Secrets** or **SOPS**.
* Adopt **GitOps (ArgoCD or Flux)** for deployment automation.

---

## ✅ Quick Checklist

* [ ] All nodes `Ready`
* [ ] `kube-system` healthy
* [ ] Longhorn healthy
* [ ] TLS certs active
* [ ] Grafana dashboards reachable
* [ ] Backups verified

---

## 🧠 Closing Thoughts

This setup is intentionally modular — built once, reusable everywhere.
It’s lean, fast, and simple to extend — just how K3s was meant to be.

> *"Jehovah provides the wisdom; we just write the playbooks."* 🙏

---

```

---

Would you like me to generate a downloadable `.md` file for this content now (so you can upload it straight to your GitHub repo)?
```
