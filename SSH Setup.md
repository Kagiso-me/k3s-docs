# K3s Cluster Management Guide
# Setting up SSH on the cluster nodes

This guide covers the setup of passwordless SSH configuration from a Raspberry Pi (`control-node`) to the cluster nodes (`tywin`, `jaime`, `tyrion`). It also includes best practices for secure and automated operations.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Network and Host Configuration](#network-and-host-configuration)
3. [Setting up Passwordless SSH for Ansible](#setting-up-passwordless-ssh-for-ansible)
4. [K3s Cluster Overview](#k3s-cluster-overview)
5. [Ansible Inventory Setup](#ansible-inventory-setup)
6. [Testing Ansible Connectivity](#testing-ansible-connectivity)
7. [Security Recommendations](#security-recommendations)

---

## Network and Host Configuration

| Node   | IP Address | Role         |
| ------ | ---------- | ------------ |
| tywin  | 10.0.10.11  | Master       |
| jaime  | 10.0.10.12  | Worker       |
| tyrion | 10.0.10.13  | Worker       |
| rpi    | 10.0.10.10  | Ansible Host |


Update /etc/hosts on the Raspberry Pi to resolve hostnames:

```bash
sudo nano /etc/hosts
``` 
Add the following entries:

```bash
10.0.10.11 tywin
10.0.10.12 jaime
10.0.10.13 tyrion
``` 

## Setting up Passwordless SSH for Ansible

To enable Ansible to manage your K3s nodes from your Raspberry Pi, configure passwordless SSH.

    1. Generate SSH Keys on the Raspberry Pi.
        ```bash
        ssh-keygen -t ed25519 -C "rpi-ansible-key"
        ``` 
        - Press Enter to accept the default location (~/.ssh/id_ed25519).
        - Optionally set a passphrase or leave it empty for fully automated login.

    2. Copy the Public Key to Each Node.
        ```bash
        ssh-copy-id -i ~/.ssh/id_ed25519.pub user@tywin
        ssh-copy-id -i ~/.ssh/id_ed25519.pub user@jaime
        ssh-copy-id -i ~/.ssh/id_ed25519.pub user@tyrion
        ``` 
        - Replace kagiso with your actual SSH username if different.

    3. Test Passwordless SSH.
        Verify that you can log in without a password:
        
        ```bash
        ssh tywin
        ssh jaime
        ssh tyrion
        ``` 
        - You should connect directly without being prompted for a password. Use exit to return to the rpi.


    4. Optional: Disable Password Authentication on Nodes.
        For enhanced security:

        1. Edit SSH config on each node:
        
        ```bash
        sudo nano /etc/ssh/sshd_config
        ``` 

        2. Set:
        
        ```bash
        PasswordAuthentication no
        ChallengeResponseAuthentication no

        ``` 
        - You should connect directly without being prompted for a password. Use exit to return to the rpi.
        - Optionally set a passphrase or leave it empty for fully automated login.

         3. Restart SSH service:
        
        ```bash
        sudo systemctl restart ssh
        ``` 
        - Ensure your SSH key works before disabling password login to avoid being locked out!


- Raspberry Pi (`rpi`) as your Ansible control node.
- K3s nodes:
  - `tywin` (master/server)
  - `jaime` (worker)
  - `tyrion` (worker)
- SSH access to all nodes.
- Ansible installed on the Raspberry Pi:

```bash
sudo apt update && sudo apt install ansible -y
``` 