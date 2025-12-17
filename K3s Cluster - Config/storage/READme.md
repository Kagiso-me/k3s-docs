# NFS Provisioners Setup for K3s (TrueNAS SSD Pool)

This guide documents the creation of **three separate NFS dynamic storage provisioners** for your SSD dataset structure in TrueNAS.

Your datasets:

```
/mnt/core/k3s/config
/mnt/core/k3s/database
/mnt/core/k3s/app_data
```

Your goal:

* Use each dataset independently for better organisation and performance.
* Automatically provision PVCs using the correct dataset via three StorageClasses.
* Maintain clarity, safety, and predictable behaviour in your K3s cluster.

This README explains **why we do it this way**, **how it works**, and **how to deploy everything**.

---

## 🧠 Why Three Provisioners?

We split the provisioners because **each dataset serves a different purpose**, and combining them into a single provisioner causes:

### ✔ 1. Clean folder separation

PVCs from different apps won’t mix under one directory. Example:

```
/mnt/core/k3s/config/*  → config PVCs
/mnt/core/k3s/database/* → DB PVCs
/mnt/core/k3s/app_data/* → application data PVCs
```

Much easier to manage, back up, snapshot, and debug.

### ✔ 2. Permissions and security isolation

Some workloads (like MariaDB/Postgres) need different permissions than apps like Nextcloud.
Different provisioners let you fine‑tune ACLs per dataset.

### ✔ 3. Different performance expectations

* **config** → tiny files, low I/O
* **database** → heavy I/O, synchronous writes
* **app_data** → large file storage (e.g., Nextcloud, Photoprism)

Keeping them separate ensures optimal behaviour.

### ✔ 4. TrueNAS dataset‑level snapshots

You can snapshot each dataset independently.

### ✔ 5. Clear Kubernetes StorageClasses

Apps select their correct dataset simply by choosing the right StorageClass.

This is not “too many” provisioners — each is tiny and uses almost no CPU/RAM.
This is **normal and recommended** for real homelab architecture.

---

## 📂 Directory Layout on TrueNAS

Before deploying provisioners, confirm your dataset paths:

```
/mnt/core/k3s/config
/mnt/core/k3s/database
/mnt/core/k3s/app_data
```

Each provisioner will dynamically create subdirectories inside its dataset:

```
/mnt/core/k3s/config/<pvc-name>/
/mnt/core/k3s/database/<pvc-name>/
/mnt/core/k3s/app_data/<pvc-name>/
```

---

## 📦 Namespace Setup

We keep provisioners in a dedicated namespace:

```sh
kubectl create namespace storage
```

Why?

* Clean separation
* Easy upgrades & management
* Easier to find all storage components

---

## 🚀 Deploying the 3 Provisioners

You will create:

* **nfs-core-config** — for config files
* **nfs-core-db** — for databases
* **nfs-core-appdata** — for large application data

Each provisioner requires its own values YAML.

### 1️⃣ nfs-core-config

`values-config.yaml`:

```yaml
nfs:
  server: 10.0.10.80
  path: /mnt/core/k3s/config

storageClass:
  name: nfs-core-config
  defaultClass: false
  allowVolumeExpansion: true
  reclaimPolicy: Retain
```

Install:

```sh
helm install nfs-core-config \
  nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  -f values-config.yaml -n storage
```

---

### 2️⃣ nfs-core-db

`values-db.yaml`:

```yaml
nfs:
  server: 10.0.10.80
  path: /mnt/core/k3s/databases

storageClass:
  name: nfs-core-db
  defaultClass: false
  allowVolumeExpansion: true
  reclaimPolicy: Retain
```

Install:

```sh
helm install nfs-core-db \
  nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  -f values-db.yaml -n storage
```

---

### 3️⃣ nfs-core-appdata

`values-appdata.yaml`:

```yaml
nfs:
  server: 10.0.10.80
  path: /mnt/core/k3s/app_data

storageClass:
  name: nfs-core-appdata
  defaultClass: true
  allowVolumeExpansion: true
  reclaimPolicy: Retain
```

Install:

```sh
helm install nfs-core-appdata \
  nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  -f values-appdata.yaml -n storage
```

---

## 🛠 Using the StorageClasses in Deployments

Example PVC for config data:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nextcloud-config
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: nfs-core-config
  resources:
    requests:
      storage: 1Gi
```

Example PVC for database:

```yaml
spec:
  storageClassName: nfs-core-db
```

Example PVC for app data:

```yaml
spec:
  storageClassName: nfs-core-appdata
```

---

## 🧹 Removing a Provisioner

Example:

```sh
helm uninstall nfs-core-config -n storage
```

This does **not** delete data on TrueNAS.

---

## 🎉 Summary

You now have:

* ✔ 3 dedicated provisioners
* ✔ Clean separation per dataset
* ✔ Safe snapshot/backup structure
* ✔ Optimal performance per workload type
* ✔ Simple PVC usage for apps

This is a **production-grade** setup — extremely clean and future‑proof.

---

If you want, I can also generate:

* Diagrams
* Example full Nextcloud deployment
* Automated backup policies
* TrueNAS snapshot schedules

## 🏗️ Architecture Diagram

```
         ┌────────────────────────────────────────────┐
         │                 TrueNAS                    │
         │────────────────────────────────────────────│
         │                                            │
         │   SSD Pool (core)                          │
         │    ├── /mnt/core/k3s/config      (NFS PV)  │
         │    │      ↑                                │
         │    │   nfs-core-config (SC)                │
         │    │                                       │
         │    ├── /mnt/core/k3s/database    (NFS PV)  │
         │    │      ↑                                │
         │    │   nfs-core-db (SC)                    │
         │    │                                       │
         │    └── /mnt/core/k3s/appdata     (NFS PV)  │
         │           ↑                                │
         │       nfs-core-appdata (SC)                │
         │                                            │
         │   HDD Pool (mass storage)                  │
         │    └── /mnt/mass/media           (NFS PV)  │
         │           ↑                                │
         │       nfs-hdd-media (SC)                   │
         └────────────────────────────────────────────┘
                          ▲
                          │  NFS Mounts
                          │
         ┌────────────────────────────────────────────┐
         │                 K3s Cluster                │
         │────────────────────────────────────────────│
         │                                            │
         │   Apps & Deployments                       │
         │                                            │
         │   - Nextcloud   → pvc-config → nfs-core-config
         │                → pvc-db     → nfs-core-db
         │                → pvc-data   → nfs-core-appdata
         │                                            │
         └────────────────────────────────────────────┘
```

---

## 📦 Example PVC + Deployment Templates

Below are **production‑ready** manifests for the most common apps in your K3s cluster.

---

# 1️⃣ Nextcloud

### PVCs

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nextcloud-config
spec:
  accessModes: [ "ReadWriteMany" ]
  storageClassName: nfs-core-config
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nextcloud-db
spec:
  accessModes: [ "ReadWriteMany" ]
  storageClassName: nfs-core-db
  resources:
    requests:
      storage: 10Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: nextcloud-appdata
spec:
  accessModes: [ "ReadWriteMany" ]
  storageClassName: nfs-core-appdata
  resources:
    requests:
      storage: 50Gi
```

### Deployment (app container only)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nextcloud
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nextcloud
  template:
    metadata:
      labels:
        app: nextcloud
    spec:
      containers:
      - name: nextcloud
        image: nextcloud:28
        volumeMounts:
        - name: config
          mountPath: /var/www/html/config
        - name: appdata
          mountPath: /var/www/html/data
      volumes:
      - name: config
        persistentVolumeClaim:
          claimName: nextcloud-config
      - name: appdata
        persistentVolumeClaim:
          claimName: nextcloud-appdata
```
---
