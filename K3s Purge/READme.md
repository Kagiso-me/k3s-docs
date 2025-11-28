# K3s Node Preparation & Purge Playbooks

**Ansible playbooks** to prepare your nodes for a K3s installation and to fully purge K3s if needed.

---

## Playbooks

### `purge-k3s.yml`
This playbook completely removes K3s from all nodes (servers and agents). It is useful if you need to reset your cluster or start fresh.

**Tasks performed:**
- Stops and disables `k3s` and `k3s-agent` services.
- Removes K3s binaries, systemd service files, and all cluster data directories.
- Cleans up leftover CNI network interfaces.
- Flushes iptables rules created by K3s.

**Why this is important:**
If you encounter issues with a K3s installation, or want to rebuild your cluster from scratch, this ensures that **all traces of K3s are removed**, avoiding conflicts with a fresh install.

---

## Usage:

### 🪪 Inventory file (inventory.ini)

```ini
[master]
tywin ansible_host=10.0.10.11 ansible_user=kagiso

[workers]
jaime ansible_host=10.0.10.12 ansible_user=kagiso
tyrion ansible_host=10.0.10.13 ansible_user=kagiso
#Node still being build - not live yet- cersei ansible_host=10.0.10.14 ansible_user=kagiso

[all:vars]
ansible_python_interpreter=/usr/bin/python3
````

### 🪪 k3s-purge playbook (purge-k3s.yml)

```bash
---
- name: Purge K3s from all nodes
  hosts: all
  become: yes
  tasks:
    - name: Stop K3s service if running
      ansible.builtin.systemd:
        name: k3s
        state: stopped
        enabled: no
      ignore_errors: yes

    - name: Stop K3s agent service if running
      ansible.builtin.systemd:
        name: k3s-agent
        state: stopped
        enabled: no
      ignore_errors: yes

    - name: Remove K3s binary
      ansible.builtin.file:
        path: /usr/local/bin/k3s
        state: absent

    - name: Remove K3s symlinks
      ansible.builtin.file:
        path: /etc/systemd/system/k3s.service
        state: absent
      ignore_errors: yes

    - name: Remove K3s agent symlinks
      ansible.builtin.file:
        path: /etc/systemd/system/k3s-agent.service
        state: absent
      ignore_errors: yes

    - name: Remove K3s data directories
      ansible.builtin.file:
        path: "{{ item }}"
        state: absent
      loop:
        - /etc/rancher/k3s
        - /var/lib/rancher/k3s
        - /var/lib/kubelet
        - /var/lib/kube-proxy
        - /var/lib/cni
        - /var/lib/calico
        - /var/lib/containerd
        - /var/run/k3s
        - /var/log/k3s

    - name: Reload systemd after removing services
      ansible.builtin.systemd:
        daemon_reload: yes

    - name: Remove leftover CNI network interfaces
      ansible.builtin.shell: |
        ip link | grep cni | awk '{print $2}' | sed 's/://' | xargs -r ip link delete
      ignore_errors: yes

    - name: Remove iptables rules set by K3s
      ansible.builtin.shell: iptables -F
      ignore_errors: yes

    - name: Remove iptables NAT table rules set by K3s
      ansible.builtin.shell: iptables -t nat -F
      ignore_errors: yes

    - name: Remove iptables mangle table rules set by K3s
      ansible.builtin.shell: iptables -t mangle -F
      ignore_errors: yes

    - name: Remove iptables raw table rules set by K3s
      ansible.builtin.shell: iptables -t raw -F
      ignore_errors: yes
```

**Purge K3s from all nodes (if needed):**
```bash
ansible-playbook -i inventory.ini purge-k3s.yml
```
---
