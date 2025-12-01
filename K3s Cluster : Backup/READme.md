# K3s Cluster Backup Guide

## 1. Purpose of Backups

Backups are critical for **any production or development cluster** to ensure:

- **Data integrity and recovery**: If a node fails, etcd database corruption occurs, or manifests are lost, backups allow full restoration.  
- **Disaster recovery**: Hardware failures, accidental deletions, or misconfigurations can be recovered quickly.  
- **Operational continuity**: Ensures Kubernetes workloads, persistent volumes, and cluster state are safe.  
- **Audit and compliance**: Regular snapshots and manifests provide a historical record of cluster configuration.

In a K3s environment:

- The **etcd database** stores all cluster state. Losing etcd means losing all deployments, services, secrets, and configurations.  
- **Kubernetes manifests** reflect the deployed resources across all namespaces.  
- **Worker node data** (like agent directories) ensures that node-specific configurations are recoverable.  
- **Persistent volumes (PV)** store application data. Losing PV data may mean application data loss.

---

## 2. Why We Set It Up This Way

### 2.1 Centralized Backup Location
- All backups are stored on a **TrueNAS NFS share**: `/mnt/tera/backups/k3s`.  
- Centralizing backups ensures:
  - **Consistency**: All cluster data is in one place.  
  - **Ease of management**: Only one system to maintain and monitor.  
  - **Scalability**: Adding new nodes or clusters can use the same backup infrastructure.  

### 2.2 Tywin as the Backup Coordinator
- Only **Tywin (K3s master node)** interacts directly with the NFS share.  
- Reasons:
  - **Single point of orchestration avoids conflicts** from multiple nodes writing to the same share simultaneously.  
  - Reduces permission issues with NFS (`root_squash` and ownership).  
  - Simplifies cron job management for automated tasks.

### 2.3 Automated Cron Jobs
- Etcd snapshots, manifests, node agent backups, and PV backups are scheduled daily.  
- Automation ensures:
  - **Regular backups without manual intervention**.  
  - **Consistency**: backups occur at set times.  
  - **Predictability**: easy to monitor and audit.

### 2.4 Separation of Concerns
Backup directories are separated by type:

```bash
/mnt/tera/backups/k3s/
├─ snapshots/ # Etcd database snapshots
├─ manifests/ # Kubernetes manifests (all resources)
├─ nodes/
│ ├─ jaime/ # Worker agent backup for Jaime
│ └─ tyrion/ # Worker agent backup for Tyrion
└─ pv/ # Persistent volume backups (NFS PVs)
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

---

## 4. Permissions and NFS Considerations
- NFS share must allow **Tywin write access**.  
- Ownership on TrueNAS: `root:root` or the UID/GID used by Ansible/cron.  
- Permissions: `755` for directories ensures readability and write capability.  
- Directory structure must exist prior to cron job execution.

---

## 5. Restoration Strategy
- **Etcd snapshot restore**: Use `k3s etcd-snapshot restore --name <snapshot>` to restore cluster state.  
- **Manifests restore**: `kubectl apply -f <manifest.yaml>` for individual or all resources.  
- **Worker node restore**: Rsync back the agent directories to nodes if rebuilding them.  
- **PV restore**: Rsync data back to the PV mount points.

---

## 6. Visual Flow of Backups

```mermaid
flowchart TD
    subgraph Cluster
        Tywin[Tywin (Master)]
        Jaime[Jaime (Worker)]
        Tyrion[Tyrion (Worker)]
    end

    subgraph NFS["TrueNAS Backup Share\n/mnt/tera/backups/k3s"]
        Snapshots[Snapshots/]
        Manifests[Manifests/]
        Nodes[Nodes/]
        PV[PV/]
    end

    %% Etcd snapshots
    Tywin -->|Daily etcd snapshot| Snapshots

    %% Manifests
    Tywin -->|Daily manifests export| Manifests

    %% Worker agent backup
    Tywin -->|Rsync agent directories| Nodes
    Jaime -->|agent data| Tywin
    Tyrion -->|agent data| Tywin

    %% PV backup
    Tywin -->|Rsync PV data| PV
```
