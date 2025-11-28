# 🧩 K3s Production-Ready Cluster — Automated with Ansible

> _“Infrastructure that feels like magic — but is actually just well-written YAML.”_

This README documents how to **automate your K3s cluster setup using Ansible**, followed by a few optional steps to make the cluster that much more **secure, scalable, and production-ready**.

Once the cluster is up (by the end of **Phase 3**), all operations and add-ons will be handled from the control host (`RPi`) using `kubectl`.

---
## ⚙️ Cluster Topology

| Role   | Hostname | IP Address  | Specs                     |
|---------|-----------|-------------|----------------------------|
| Server / Master | `tywin` | 10.0.10.11 | Intel NUC (i3-5010U, 12 GB RAM) |
| Worker | `jaime` | 10.0.10.12 | Lenovo ThinkCentre (i5-4570T, 16 GB RAM) |
| Worker | `tyrion` | 10.0.10.13 | Lenovo ThinkCentre (i5-4570T, 16 GB RAM) |
| Control / Ansible host / kubectl | `varys` | 10.0.10.10 | Raspberry Pi 3B+ |

---

## 🧭 Phase 1 — Preparing Nodes with Ansible

### 🔑 Why this phase matters
Before we can let Ansible do its thing, every node needs to be ready for remote orchestration.  
Ansible communicates over SSH and executes Python code on the target — **so we must ensure SSH and Python are ready**. See SSH guide - ***"[SSH Setup](https://github.com/Kagiso-me/k3s-docs/blob/master/SSH%20Setup.md)".***  

---

### 🪪 Inventory file (inventory.ini)

```ini
[master]
tywin ansible_host=10.0.10.11 ansible_user=kagiso

[workers]
jaime ansible_host=10.0.10.12 ansible_user=kagiso
tyrion ansible_host=10.0.10.13 ansible_user=kagiso

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
    - name: Ensure essential tools are installed
      ansible.builtin.apt:
        name: [curl, iptables, nfs-common]
        state: present
        
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

Now that the nodes are prepped, let’s install K3s using a playbook - fully automated.

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
          --tls-san 10.0.10.11 \
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
        curl -sfL https://get.k3s.io | K3S_URL=https://10.0.10.11:6443 \
        K3S_TOKEN={{ token_file['content'] | b64decode }} sh -
      args:
        creates: /usr/local/bin/k3s-agent


####################################################################
# Retrieve kubeconfig from master onto Ansible host
####################################################################
- name: Retrieve kubeconfig from master
  hosts: master
  tasks:
    - name: Fetch kubeconfig
      become: yes
      ansible.builtin.fetch:
        src: /etc/rancher/k3s/k3s.yaml
        dest: "{{ lookup('env','HOME') }}/kubeconfig"
        flat: yes


####################################################################
# Fix kubeconfig + install kubectl on the controller (RPi)
####################################################################
- name: Prepare kubeconfig and install kubectl
  hosts: localhost
  tasks:
    - name: Replace localhost with master IP in kubeconfig
      ansible.builtin.replace:
        path: "{{ lookup('env','HOME') }}/kubeconfig"
        regexp: '127\.0\.0\.1'
        replace: '10.0.10.11'

    - name: Check if kubectl exists
      ansible.builtin.command: kubectl version --client --short
      register: kubectl_check
      ignore_errors: true

    - name: Install kubectl for kagiso user (no sudo)
      ansible.builtin.shell: |
        set -e
        ARCH=arm64
        VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)

        # Download kubectl binary + checksum
        curl -LO "https://dl.k8s.io/release/$VERSION/bin/linux/${ARCH}/kubectl"
        curl -LO "https://dl.k8s.io/release/$VERSION/bin/linux/${ARCH}/kubectl.sha256"

        # Verify checksum
        echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check

        # Install locally without sudo
        chmod +x kubectl
        mkdir -p ~/.local/bin
        mv kubectl ~/.local/bin/kubectl
      args:
        executable: /bin/bash
      when: kubectl_check.rc != 0

```

---
Run it:

```bash
ansible-playbook -i inventory.ini install-k3s.yml
```

At this stage - the k3s cluster is up and can be managed from the kubectl node. 
The following are additional steps to further fine-tune the cluster. 

## 🧩 Phase 3 — Verify and Label Cluster

After installation, you can now manage the cluster from your control host (`RPi`).

### Verify nodes

```bash
kubectl get nodes -o wide
```

### Label & taint

```bash
kubectl label node tywin role=master
kubectl label node jaime role=worker
kubectl label node tyrion role=worker
#kubectl label node cersei role=worker
kubectl taint nodes tywin node-role.kubernetes.io/master=:NoSchedule
```

✅ This ensures workloads only run on your workers by default, keeping the control plane clean.

---

## 🌐 Phase 4 — To be updated (Redacted)





## 💾 Phase 5 — Backups & DR

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

## 🧠 Closing Thoughts

This setup is intentionally modular — built once, reusable everywhere.
It’s lean, fast, and simple to extend — just how K3s was meant to be.

---
