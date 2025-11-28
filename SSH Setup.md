# Setting up SSH on the cluster nodes

This guide covers the setup of passwordless SSH configuration from a Raspberry Pi (`control-node`) to the cluster nodes (`tywin`, `jaime`, `tyrion`, `cersei`). It also includes best practices for secure and automated operations.

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
---
## Setting up Passwordless SSH for Ansible

To enable Ansible to manage your K3s nodes from your Raspberry Pi, configure passwordless SSH.

### 1. Generate SSH Keys on the Raspberry Pi.
```bash
        ssh-keygen -t ed25519 -C "ansible-key"
``` 
---
- Press Enter to accept the default location (~/.ssh/id_ed25519).
- Optionally set a passphrase or leave it empty for fully automated login.

### 2. Copy the Public Key to Each Node.
```bash
        ssh-copy-id -i ~/.ssh/id_ed25519.pub user@tywin
        ssh-copy-id -i ~/.ssh/id_ed25519.pub user@jaime
        ssh-copy-id -i ~/.ssh/id_ed25519.pub user@tyrion
``` 
---

- Replace "user" with your actual SSH username if different.

### 3. Test Passwordless SSH.
Verify that you can log in without a password:
        
```bash
        ssh tywin
        ssh jaime
        ssh tyrion
``` 
---
- You should connect directly without being prompted for a password.


## Optional: Disable Password Authentication on Nodes
For enhanced security:

4.1. Edit SSH config on each node:
        
```bash
        sudo nano /etc/ssh/sshd_config
``` 
4.2. Set:
        
```bash
        PasswordAuthentication no
        ChallengeResponseAuthentication no
``` 

4.3. Restart SSH service:
        
```bash
        sudo systemctl restart ssh
``` 
- Ensure your SSH key works before disabling password login to avoid being locked out!
