# 🚀 K3s Cluster Backup Guide

> Backups are your cluster’s **life insurance policy**. Let’s make sure yours is bulletproof! 🔒

---

## 1️⃣ Why Backups Matter

Backups are critical for **any production or dev cluster**. Without them, disaster could strike at any moment.

| Icon | Purpose | What It Protects |
|------|---------|-----------------|
| 🛡️ | **Data Integrity & Recovery** | Node failures, etcd corruption, lost manifests |
| 🔥 | **Disaster Recovery** | Hardware failure, accidental deletions, misconfigurations |
| ⚙️ | **Operational Continuity** | Workloads, PVs, cluster state |
| 📜 | **Audit & Compliance** | Track historical cluster configuration |

**Key K3s Considerations:**

- **etcd database**: Everything lives here. Lose etcd = lose cluster state.  
- **Manifests**: Snapshot of all deployed resources across namespaces.  
- **Worker node data**: Node-specific configs are critical for smooth restores.  
- **Persistent Volumes (PV)**: Your apps’ data — don’t lose it!  

---

## 2️⃣ Backup Architecture 🏗️

### 2.1 Centralized Backup Location

- Location: **TrueNAS NFS share** → `/mnt/tera/backups/k3s`  
- **Why centralize?**
  - ✅ Consistency: Everything in one place  
  - ✅ Easy management: Monitor one system  
  - ✅ Scalable: Add new nodes/clusters without extra setup  

### 2.2 Tywin as the Backup Coordinator

- Tywin (K3s master) is the **single point of orchestration**.  
- Benefits:
  - Avoids NFS conflicts 🚫  
  - Simplifies permissions & cron jobs  
  - Streamlines automation  

### 2.3 Automated Cron Jobs ⏰

- Scheduled daily:
  - **Etcd snapshots** → 02:00  
  - **Manifests** → 03:00  
  - **Worker agents** → 04:00  
  - **PVs** → 05:00  
- **Advantages:**
  - No manual intervention  
  - Predictable & auditable  
  - Consistent, reliable backups  

### 2.4 Organized Backup Directories 📁

```bash
/mnt/tera/backups/k3s/
├─ snapshots/   # Etcd database snapshots
├─ manifests/   # Kubernetes manifests (all namespaces)
├─ nodes/
│  ├─ jaime/    # Worker agent backup for Jaime
│  └─ tyrion/   # Worker agent backup for Tyrion
└─ pv/          # Persistent volume backups (NFS PVs)
```

- Keeps backups **organized and manageable**.  
- Makes **restore operations easier**, since you know where each type of data is located.

---

## 3. Backup Strategy

### 3.1 Etcd Snapshots
- Taken from the master node (Tywin) daily at 02:00.  
- Stored in `snapshots/` directory.  
- **Purpose**: Capture full cluster state.  
- **Retention suggestion**: Keep the last 7–14 snapshots for recovery.

### 3.2 Manifests Backup
- Daily at 03:00, all resources (`kubectl get all --all-namespaces -o yaml`) are exported to `manifests/`.  
- **Purpose**: Provides a human-readable backup of deployed resources.  
- **Benefit**: Allows partial restore of resources or audit of changes over time.

### 3.3 Worker Agent Backup
- Daily at 04:00, Tywin rsyncs `/var/lib/rancher/k3s/agent` directories from all worker nodes (`jaime`, `tyrion`) to `nodes/`.  
- **Purpose**: Capture node-specific configurations.  
- **Benefit**: Ensures worker nodes can be restored or replaced with minimal effort.

### 3.4 Persistent Volume Backup
- Daily at 05:00, PVs from `/mnt/nfs-pv/` are rsynced to `pv/`.  
- **Purpose**: Preserve application data stored on PVs.  
- **Benefit**: Application recovery without data loss.  

### 3.5 Backup Flow
1. Tywin executes cron jobs on schedule.  
2. Each backup type is stored in its dedicated directory.  
3. Files are versioned using timestamps (`YYYY-MM-DD_HH-MM-SS`) for snapshots and manifests.  
4. PVs are synced using rsync to ensure incremental updates.
5. 
```bash
Diagram to be uploaded!
```
---

## 4. Permissions and NFS Considerations
- NFS share must allow **Tywin write access**.  
- Ownership on TrueNAS: `root:root` or the UID/GID used by Ansible/cron.  
- Permissions: `755` for directories ensures readability and write capability.  

---

## 5. Restoration Strategy
- **Etcd snapshot restore**: Use `k3s etcd-snapshot restore --name <snapshot>` to restore cluster state.  
- **Manifests restore**: `kubectl apply -f <manifest.yaml>` for individual or all resources.  
- **Worker node restore**: Rsync back the agent directories to nodes if rebuilding them.  
- **PV restore**: Rsync data back to the PV mount points.

---

