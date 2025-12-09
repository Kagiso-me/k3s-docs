# 🚀 K3s Cluster Backup Guide

> Backups are your cluster’s **life insurance policy**. Let’s make sure yours is bulletproof! 🔒

---

## 1️⃣ Why Backups Matter

Backups are critical for **any production or dev cluster**. Without them, disaster could strike at any moment.

| Icon | Purpose                       | What It Protects                                          |
| ---- | ----------------------------- | --------------------------------------------------------- |
| 🛡️  | **Data Integrity & Recovery** | Node failures, SQLite DB corruption, lost manifests       |
| 🔥   | **Disaster Recovery**         | Hardware failure, accidental deletions, misconfigurations |
| ⚙️   | **Operational Continuity**    | Workloads, PVs, cluster state                             |
| 📜   | **Audit & Compliance**        | Track historical cluster configuration                    |

**Key K3s Considerations:**

* **Manifests**: Snapshot of all deployed resources across namespaces.
* **Worker node data**: Node-specific configs are critical for smooth restores.
* **Persistent Volumes (PV)**: Your apps’ data — don’t lose it!

> ⚠️ Etcd snapshots are not used — your cluster is on SQLite. Only manifests, node data, and PVs are backed up.

---

## 2️⃣ Backup Architecture 🏗️

### 2.1 Centralized Backup Location

* Location: **TrueNAS NFS share** → `/mnt/tera/backups/k3s`
* **Why centralize?**

  * ✅ Consistency: Everything in one place
  * ✅ Easy management: Monitor one system
  * ✅ Scalable: Add new nodes/clusters without extra setup

### 2.2 Tywin as the Backup Coordinator

* Tywin (K3s master) is the **single point of orchestration**.
* Benefits:

  * Avoids NFS conflicts 🚫
  * Simplifies permissions & automation
  * Streamlines backup scripts

### 2.3 Automated Backups via systemd Timer ⏰

Instead of cron, we use **systemd timers** to execute backups and metrics collection.

**Commands to manage timer:**

```bash
# Check timer
sudo systemctl status k3s-backup-metrics.timer

# Start / stop / restart
sudo systemctl start k3s-backup-metrics.timer
sudo systemctl stop k3s-backup-metrics.timer
sudo systemctl restart k3s-backup-metrics.timer

# View logs
sudo journalctl -u k3s-backup-metrics.service -f
```

---

### 2.4 Organized Backup Directories 📁

```bash
/mnt/tera/backups/k3s/
├─ manifests/   # Kubernetes manifests (all namespaces)
├─ nodes/
│  ├─ jaime/    # Worker agent backup for Jaime
│  └─ tyrion/   # Worker agent backup for Tyrion
└─ pv/          # Persistent volume backups (NFS PVs)
```

* Keeps backups **organized and manageable**.
* Makes **restore operations easier**, since you know where each type of data is located.

---

## 3️⃣ Backup Strategy

> ⚠️ Etcd snapshot backup is skipped (SQLite cluster).

### 3.1 Manifests Backup

* Backup: `kubectl get all --all-namespaces -o yaml` → `manifests/`.
* **Purpose**: Human-readable backup of deployed resources.
* **Benefit**: Partial restore or audit over time.

### 3.2 Worker Agent Backup

* Rsync `/var/lib/rancher/k3s/agent` from all worker nodes (`jaime`, `tyrion`) → `nodes/`.
* **Purpose**: Preserve node-specific configs.
* **Benefit**: Smooth node replacement or rebuild.

### 3.3 Persistent Volume Backup

* Rsync PV data from `/mnt/nfs-pv/` → `pv/`.
* **Purpose**: Preserve application data stored on PVs.
* **Benefit**: Application recovery without data loss.

### 3.4 Backup Flow

1. Tywin executes **systemd timer** jobs.
2. Each backup type is stored in its dedicated directory.
3. Files are timestamped (`YYYY-MM-DD_HH-MM-SS`) for versioning.
4. PVs are synced incrementally using rsync.

```bash
Diagram to be uploaded!
```

---

## 4️⃣ Permissions and NFS Considerations

* NFS share must allow **Tywin write access**.
* Ownership on TrueNAS: `kagiso:kagiso` (or UID/GID used by backup scripts).
* Permissions: `755` ensures readability and write capability.

---

## 5️⃣ Restoration Strategy

* **Manifests restore**: `kubectl apply -f <manifest.yaml>`
* **Worker node restore**: Rsync agent directories back to nodes
* **PV restore**: Rsync PV data back to mount points

---

## 6️⃣ Backup Metrics Script & Prometheus Integration

Create metrics for Grafana visualization:

```bash
sudo nano /usr/local/bin/k3s-backup-metrics.sh
```

```bash
#!/bin/bash

OUT="/var/lib/node_exporter/textfile_collector/k3s_backup.prom"

mtime() {
  stat -c %Y "$1" 2>/dev/null || echo 0
}

du_size() {
  du -sb "$1" 2>/dev/null | awk '{print $1}'
}

# Write last modified times
{
  echo "# HELP k3s_backup_last_mtime Last backup file modification times"
  echo "# TYPE k3s_backup_last_mtime gauge"
  echo "k3s_backup_last_mtime{type=\"manifests\"} $(mtime /mnt/backup-tera/k3s/manifests)"
  echo "k3s_backup_last_mtime{type=\"node_jaime\"} $(mtime /mnt/backup-tera/k3s/nodes/jaime)"
  echo "k3s_backup_last_mtime{type=\"node_tyrion\"} $(mtime /mnt/backup-tera/k3s/nodes/tyrion)"
  echo "k3s_backup_last_mtime{type=\"pv_backup\"} $(mtime /mnt/backup-tera/k3s/pv)"
} > "$OUT"

# Write directory sizes
{
  echo "# HELP k3s_backup_dir_size Backup directory sizes in bytes"
  echo "# TYPE k3s_backup_dir_size gauge"
  echo "k3s_backup_dir_size{type=\"manifests\"} $(du_size /mnt/backup-tera/k3s/manifests)"
  echo "k3s_backup_dir_size{type=\"nodes\"} $(du_size /mnt/backup-tera/k3s/nodes)"
  echo "k3s_backup_dir_size{type=\"pv_backup\"} $(du_size /mnt/backup-tera/k3s/pv)"
} >> "$OUT"
```

Make executable:

```bash
sudo chmod +x /usr/local/bin/k3s-backup-metrics.sh
```

---

## 7️⃣ Manual Backup Script (SQLite Cluster)

```bash
sudo nano /home/kagiso/k3s_manual_backup.sh
```

```bash
#!/bin/bash

TIMESTAMP=$(date +"%F_%H-%M-%S")
BACKUP_DIR="/mnt/backup-tera/k3s"
LOG_FILE="/var/log/k3s-backups.log"

mkdir -p "$BACKUP_DIR/manifests" "$BACKUP_DIR/nodes/jaime" "$BACKUP_DIR/nodes/tyrion" "$BACKUP_DIR/pv"

echo "[$(date)] Starting manual backup" | tee -a "$LOG_FILE"

# Manifests backup
kubectl get all --all-namespaces -o yaml > "$BACKUP_DIR/manifests/k3s-all-resources-$TIMESTAMP.yaml"

# Worker node backups
rsync -avz jaime:/var/lib/rancher/k3s/agent "$BACKUP_DIR/nodes/jaime/" >> "$LOG_FILE" 2>&1
rsync -avz tyrion:/var/lib/rancher/k3s/agent "$BACKUP_DIR/nodes/tyrion/" >> "$LOG_FILE" 2>&1

# PV backups
rsync -avz /mnt/nfs-pv/ "$BACKUP_DIR/pv/" >> "$LOG_FILE" 2>&1

echo "[$(date)] Manual backup completed" | tee -a "$LOG_FILE"
```

Make executable:

```bash
sudo chmod +x /home/kagiso/k3s_manual_backup.sh
```

Run manually:

```bash
sudo /home/kagiso/k3s_manual_backup.sh
```

---

## 8️⃣ Central Logging

All backup and metrics scripts log to:

```bash
/var/log/k3s-backups.log
```

---

## 9️⃣ Systemd Timer Setup

**Service file** `/etc/systemd/system/k3s-backup-metrics.service`:

```ini
[Unit]
Description=Run K3s Backup Metrics

[Service]
Type=oneshot
ExecStart=/usr/local/bin/k3s-backup-metrics.sh
```

**Timer file** `/etc/systemd/system/k3s-backup-metrics.timer`:

```ini
[Unit]
Description=Run K3s Backup Metrics Every 5 Minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min
Unit=k3s-backup-metrics.service

[Install]
WantedBy=timers.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now k3s-backup-metrics.timer
```

This ensures Prometheus always gets updated metrics automatically.

---

## 🔹 End of Guide
