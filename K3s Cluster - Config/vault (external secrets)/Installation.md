# HashiCorp Vault on Raspberry Pi (SSD Boot) – Full Raft Guide

This guide installs Vault in **Raft mode** on a Raspberry Pi that is already running from an external SSD. No formatting, wiping, or new partitions are required.

We simply isolate Vault's storage using a dedicated directory (`/srv/vault`) on the same SSD.

---

# 1. System Requirements

* Running Raspberry Pi OS / Ubuntu Server **on an external SSD** (already done)
* Internet access to download Vault
* Root or sudo access

This RPi is also your:

* kubectl node
* Prometheus/Grafana node

Vault will run fine alongside these.

---

# 2. Create Vault Directory Structure

We create an isolated directory tree under `/srv/vault` for clean separation.

```bash
sudo mkdir -p /srv/vault/raft
sudo mkdir -p /srv/vault/config
sudo mkdir -p /srv/vault/logs
sudo chown -R vault:vault /srv/vault || true
```

We will create the `vault` user later; for now this is fine.

---

# 3. Create Vault User

Vault should **not** run as root.

```bash
sudo useradd --system --home /srv/vault --shell /bin/false vault
sudo chown -R vault:vault /srv/vault
```

---

# 4. Install Vault (Binary Install)

## Download Vault

```bash
sudo apt update
sudo apt install -y unzip curl

curl -Lo vault.zip https://releases.hashicorp.com/vault/1.17.0/vault_1.17.0_linux_arm64.zip
unzip vault.zip
sudo mv vault /usr/local/bin/
sudo chmod 755 /usr/local/bin/vault
```

## Create vault directories

```bash
sudo mkdir -p /etc/vault.d
sudo chown -R vault:vault /etc/vault.d
```

---

# 5. Vault Configuration (Raft Storage Backend)

Create `/etc/vault.d/vault.hcl`:

```hcl
ui = true
api_addr = "http://0.0.0.0:8200"
cluster_addr = "http://<YOUR_RPI_IP>:8201" # Replace with Pi IP

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

storage "raft" {
  path    = "/srv/vault/raft"
  node_id = "rpi1"
}

log_level = "info"
```

Give correct permissions:

```bash
sudo chown -R vault:vault /etc/vault.d
sudo chmod 640 /etc/vault.d/vault.hcl
```

---

# 6. Systemd Service

Create `/etc/systemd/system/vault.service`:

```ini
[Unit]
Description=HashiCorp Vault
Requires=network-online.target
After=network-online.target

[Service]
User=vault
Group=vault
ProtectSystem=full
ProtectHome=read-only
PrivateTmp=yes
AmbientCapabilities=CAP_IPC_LOCK
CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK
SecureBits=keep-caps
ExecStart=/usr/local/bin/vault server -config=/etc/vault.d/vault.hcl
ExecReload=/bin/kill --signal HUP $MAINPID
LimitNOFILE=65536
LimitMEMLOCK=infinity
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Reload systemd and enable Vault:

```bash
sudo systemctl daemon-reload
sudo systemctl enable vault
sudo systemctl start vault
```

Check status:

```bash
systemctl status vault
```

---

# 7. Initialize & Unseal Vault (Raft)

## Initialize

```bash
export VAULT_ADDR="http://127.0.0.1:8200"
vault operator init
```

This produces:

* Recovery keys (store safely!)
* Initial root token

## Unseal using recovery keys

Run:

```bash
vault operator unseal
vault operator unseal
vault operator unseal
```

(3 of 5 is the default threshold)

Then login:

```bash
vault login
```

---

# 8. Auto-Unseal Options

Because you are running Vault in Raft mode, we use **SSS recovery keys**.

Safe options:

### Option A — Keep manual unseal (simple, recommended for homelab)

* No added services required
* Perfectly fine for a single RPi node

### Option B — Use Transit Auto-Unseal **from this same Vault**

Not recommended — chicken and egg problem.

### Option C — Use Cloud KMS (Google / AWS / Azure)

Only needed for enterprise-like infra.

**Recommended for you: stick with manual unseal.**

---

# 9. Backup & Snapshot Strategy (Raft)

Vault Raft supports built-in snapshots.

## Create snapshot directory

```bash
sudo mkdir -p /srv/vault/snapshots
sudo chown -R vault:vault /srv/vault/snapshots
```

## Create snapshot script

Create `/usr/local/bin/vault-snapshot.sh`:

```bash
#!/bin/bash
TIMESTAMP=$(date +"%Y-%m-%d-%H-%M-%S")
SNAP="/srv/vault/snapshots/vault-$TIMESTAMP.snap"
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="<YOUR-ROOT-TOKEN>"


# Create local snapshot
vault operator raft snapshot save "$SNAP"


# Optional: Rsync snapshot to TrueNAS
rsync -avz --no-perms /srv/vault/snapshots/ kagiso@10.0.10.80:/mnt/tera/backups/vault/
```

```bash
sudo chmod +x /usr/local/bin/vault-snapshot.sh
```

* `TIMESTAMP` → unique filename for each snapshot
* `VAULT_TOKEN` → replace with Vault token that has snapshot privileges
* `--no-perms` → avoids permission errors on ZFS/TrueNAS
* `rsync` → synchronizes snapshots to TrueNAS for offsite backup

## Add cronjob for daily snapshot

```bash
sudo crontab -e
```

Add:

```
0 2 * * * /usr/local/bin/vault-snapshot.sh
```

This ensures:

* A snapshot is created locally on the Pi every day at 2:00 AM
* Snapshots are automatically rsynced to TrueNAS
* Unique timestamped files prevent overwriting previous snapshots

# 10. Network Exposure Rules

### Allow ONLY LAN access

On the RPi:

```bash
sudo ufw allow from 10.0.0.0/24 to any port 8200 proto tcp
sudo ufw allow from 10.0.0.0/24 to any port 8201 proto tcp
sudo ufw deny 8200/tcp
sudo ufw enable
```

### Do **NOT** expose Vault publicly.

Vault should stay inside your LAN.

---

# 11. Using Vault with K3s

Add this to your cluster:

* Vault Agent Injector (optional)
* External Secrets Operator or Vault CSI (recommended)

You will configure:

* Auth method: Kubernetes
* Policies
* Tokens

Vault will be accessible internally at:

```
http://vault.local.kagiso.me:8200
```

Configure this in your reverse-proxy or your DNS.

---

# 12. Maintenance

### Check raft status

```bash
vault operator raft list-peers
```

### Monitor logs

```bash
journalctl -fu vault
```

### Test snapshots

```bash
vault operator raft snapshot inspect <snapfile>
```

---

# 13. Summary

* No disk formatting needed
* Use dedicated directory on SSD
* Full Raft storage
* Full systemd service
* Manual unseal (recommended)
* Built-in snapshot + offsite backup
* LAN-only exposure

---
