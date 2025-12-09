# K3s Backup Verification Dashboard

This folder contains a Grafana dashboard JSON and supporting metrics approach to **verify K3s backups** running on Tywin and stored on a TrueNAS NFS share.

The goal is to provide **fast visual confirmation** that:

* Etcd snapshots are running daily
* Cluster manifests are exported daily
* Worker node agent data is synced
* Persistent Volume data is synced
* Backup sizes look sane over time
* Backups are not stale or missing

---

## Prerequisites

You should already have:

* **K3s** running on Tywin (master) with backups going to:

  * `/mnt/backup-tera/k3s/snapshots`
  * `/mnt/backup-tera/k3s/manifests`
  * `/mnt/backup-tera/k3s/nodes/{jaime,tyrion}`
  * `/mnt/backup-tera/k3s/pv`
* **Node Exporter** running on Tywin
* **Prometheus** scraping Node Exporter
* **Grafana** connected to Prometheus

Additionally, you need to:

1. Enable the Node Exporter **textfile collector**
2. Add a small shell script to generate backup metrics
3. Configure Prometheus alert rules (optional but recommended)
4. Import the included Grafana dashboard JSON

---

## 1. Enable Node Exporter Textfile Collector

On **Tywin**, configure node_exporter to use a textfile directory, e.g.:

```bash
sudo mkdir -p /var/lib/node_exporter/textfile_collector
```

If you run node_exporter via systemd, ensure the service has:

```text
--collector.textfile.directory=/var/lib/node_exporter/textfile_collector
```

Then restart node_exporter.

## 2. Backup Metrics Script

Create the metrics script:

```bash
sudo nano /usr/local/bin/k3s_backup_metrics.sh
```

Paste the following:

```bash
#!/bin/bash

OUT="/var/lib/node_exporter/textfile_collector/k3s_backup.prom"

# helper: get last modified time (epoch)
mtime() {
  stat -c %Y "$1" 2>/dev/null || echo 0
}

# write last modified times
echo "# HELP k3s_backup_last_mtime Last backup file modification times" > "$OUT"
echo "# TYPE k3s_backup_last_mtime gauge" >> "$OUT"

echo "k3s_backup_last_mtime{type=\"etcd_snapshot\"} $(mtime /mnt/backup-tera/k3s/snapshots)" >> "$OUT"
echo "k3s_backup_last_mtime{type=\"manifests\"} $(mtime /mnt/backup-tera/k3s/manifests)" >> "$OUT"
echo "k3s_backup_last_mtime{type=\"node_jaime\"} $(mtime /mnt/backup-tera/k3s/nodes/jaime)" >> "$OUT"
echo "k3s_backup_last_mtime{type=\"node_tyrion\"} $(mtime /mnt/backup-tera/k3s/nodes/tyrion)" >> "$OUT"
echo "k3s_backup_last_mtime{type=\"pv_backup\"} $(mtime /mnt/backup-tera/k3s/pv)" >> "$OUT"

# write directory sizes
echo "" >> "$OUT"
echo "# HELP k3s_backup_dir_size Backup directory sizes in bytes" >> "$OUT"
echo "# TYPE k3s_backup_dir_size gauge" >> "$OUT"

du_size() {
  du -sb "$1" 2>/dev/null | awk '{print $1}'
}

echo "k3s_backup_dir_size{type=\"etcd_snapshot\"} $(du_size /mnt/backup-tera/k3s/snapshots)" >> "$OUT"
echo "k3s_backup_dir_size{type=\"manifests\"} $(du_size /mnt/backup-tera/k3s/manifests)" >> "$OUT"
echo "k3s_backup_dir_size{type=\"nodes\"} $(du_size /mnt/backup-tera/k3s/nodes)" >> "$OUT"
echo "k3s_backup_dir_size{type=\"pv_backup\"} $(du_size /mnt/backup-tera/k3s/pv)" >> "$OUT"
```

Make it executable:

```bash
sudo chmod +x /usr/local/bin/k3s_backup_metrics.sh
```

## 3. Cron Job for Metrics

Run the metrics script every 5 minutes so Prometheus sees fresh values:

```bash
sudo crontab -e
```

Add:

```cron
*/5 * * * * /usr/local/bin/k3s_backup_metrics.sh
```

Now Node Exporter exposes metrics:

* k3s_backup_last_mtime{type="..."}
* k3s_backup_dir_size{type="..."}

## 4. Optional: Prometheus Alert Rules

Example alert rules file (`k3s-backup-alerts.yaml`):

```yaml
groups:
- name: k3s-backup-alerts
  rules:

  - alert: K3sEtcdSnapshotStale
    expr: time() - k3s_backup_last_mtime{type="etcd_snapshot"} > 86400
    for: 10m
    labels:
      severity: warning
    annotations:
      summary: "Etcd snapshot older than 24 hours"
      description: "No recent etcd snapshot detected on Tywin."

  - alert: K3sManifestBackupStale
    expr: time() - k3s_backup_last_mtime{type="manifests"} > 86400
    for: 10m
    labels:
      severity: warning

  - alert: K3sNodeBackupStale
    expr: time() - k3s_backup_last_mtime{type=~"node_.*"} > 86400
    for: 10m
    labels:
      severity: critical

  - alert: K3sPVBackupStale
    expr: time() - k3s_backup_last_mtime{type="pv_backup"} > 86400
    for: 10m
    labels:
      severity: warning
```

Add this to your Prometheus `rule_files` and reload Prometheus.


---


## 5. Grafana Dashboard

    1. Open Grafana
    2. Go to Dashboards → Import
    3. Paste the JSON from k3s-backup-verification-dashboard.json
    4. When prompted for a data source, select your Prometheus instance
    5. Click Import
  Paste **k3s-backup-verification-dashboard.json**
    


## What the Dashboard Shows
The dashboard includes:
    -   Etcd Snapshot Age (hours) — stat panel, green/yellow/red thresholds
    -   Manifests Backup Age (hours)
    -   Node Backup Age (Jaime + Tyrion) — worst-case age
    -   PV Backup Age
    -   Total Backup Size — sum of all backup directory sizes
    -   Per-directory sizes — snapshots, manifests, nodes, PV
    -   Trends over time — growth of backup usage
This gives you a quick “is everything backing up correctly?” view plus enough
detail to debug if something looks off.

---

k3s-backup-verification-dashboard.json
```json
{
  "annotations": {
    "list": [
      {
        "builtIn": 1,
        "type": "dashboard",
        "name": "Annotations & Alerts",
        "enable": true,
        "hide": true,
        "iconColor": "rgba(0, 211, 255, 1)"
      }
    ]
  },
  "editable": true,
  "fiscalYearStartMonth": 0,
  "graphTooltip": 0,
  "id": null,
  "links": [],
  "liveNow": false,
  "panels": [
    {
      "id": 1,
      "type": "stat",
      "title": "Etcd Snapshot Age (hours)",
      "datasource": "${DS_PROMETHEUS}",
      "gridPos": { "h": 4, "w": 6, "x": 0, "y": 0 },
      "targets": [
        {
          "refId": "A",
          "expr": "(time() - k3s_backup_last_mtime{type=\"etcd_snapshot\"}) / 3600"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "unit": "h",
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "green", "value": null },
              { "color": "yellow", "value": 24 },
              { "color": "red", "value": 30 }
            ]
          }
        },
        "overrides": []
      },
      "options": {
        "colorMode": "value",
        "graphMode": "none",
        "justifyMode": "auto",
        "orientation": "horizontal",
        "reduceOptions": {
          "calcs": ["lastNotNull"],
          "fields": "",
          "values": false
        },
        "textMode": "auto"
      }
    },
    {
      "id": 2,
      "type": "stat",
      "title": "Manifests Backup Age (hours)",
      "datasource": "${DS_PROMETHEUS}",
      "gridPos": { "h": 4, "w": 6, "x": 6, "y": 0 },
      "targets": [
        {
          "refId": "A",
          "expr": "(time() - k3s_backup_last_mtime{type=\"manifests\"}) / 3600"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "unit": "h",
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "green", "value": null },
              { "color": "yellow", "value": 24 },
              { "color": "red", "value": 30 }
            ]
          }
        },
        "overrides": []
      },
      "options": {
        "colorMode": "value",
        "graphMode": "none",
        "justifyMode": "auto",
        "orientation": "horizontal",
        "reduceOptions": {
          "calcs": ["lastNotNull"],
          "fields": "",
          "values": false
        },
        "textMode": "auto"
      }
    },
    {
      "id": 3,
      "type": "stat",
      "title": "Node Backups Age (hours, worst of Jaime/Tyrion)",
      "datasource": "${DS_PROMETHEUS}",
      "gridPos": { "h": 4, "w": 6, "x": 12, "y": 0 },
      "targets": [
        {
          "refId": "A",
          "expr": "max((time() - k3s_backup_last_mtime{type=~\"node_.*\"}) / 3600)"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "unit": "h",
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "green", "value": null },
              { "color": "yellow", "value": 24 },
              { "color": "red", "value": 30 }
            ]
          }
        },
        "overrides": []
      },
      "options": {
        "colorMode": "value",
        "graphMode": "none",
        "justifyMode": "auto",
        "orientation": "horizontal",
        "reduceOptions": {
          "calcs": ["lastNotNull"],
          "fields": "",
          "values": false
        },
        "textMode": "auto"
      }
    },
    {
      "id": 4,
      "type": "stat",
      "title": "PV Backup Age (hours)",
      "datasource": "${DS_PROMETHEUS}",
      "gridPos": { "h": 4, "w": 6, "x": 18, "y": 0 },
      "targets": [
        {
          "refId": "A",
          "expr": "(time() - k3s_backup_last_mtime{type=\"pv_backup\"}) / 3600"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "unit": "h",
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "green", "value": null },
              { "color": "yellow", "value": 24 },
              { "color": "red", "value": 30 }
            ]
          }
        },
        "overrides": []
      },
      "options": {
        "colorMode": "value",
        "graphMode": "none",
        "justifyMode": "auto",
        "orientation": "horizontal",
        "reduceOptions": {
          "calcs": ["lastNotNull"],
          "fields": "",
          "values": false
        },
        "textMode": "auto"
      }
    },
    {
      "id": 5,
      "type": "stat",
      "title": "Total Backup Size",
      "datasource": "${DS_PROMETHEUS}",
      "gridPos": { "h": 4, "w": 8, "x": 0, "y": 4 },
      "targets": [
        {
          "refId": "A",
          "expr": "sum(k3s_backup_dir_size)"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "unit": "bytes",
          "decimals": 2,
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "green", "value": null },
              { "color": "yellow", "value": 5e11 },
              { "color": "red", "value": 1e12 }
            ]
          }
        },
        "overrides": []
      },
      "options": {
        "colorMode": "value",
        "graphMode": "area",
        "justifyMode": "auto",
        "orientation": "horizontal",
        "reduceOptions": {
          "calcs": ["lastNotNull"],
          "fields": "",
          "values": false
        },
        "textMode": "auto"
      }
    },
    {
      "id": 6,
      "type": "bargauge",
      "title": "Backup Directory Sizes",
      "datasource": "${DS_PROMETHEUS}",
      "gridPos": { "h": 8, "w": 16, "x": 8, "y": 4 },
      "targets": [
        {
          "refId": "A",
          "expr": "k3s_backup_dir_size"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "unit": "bytes",
          "decimals": 2,
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "green", "value": null },
              { "color": "yellow", "value": 0 },
              { "color": "red", "value": 1 }
            ]
          }
        },
        "overrides": []
      },
      "options": {
        "displayMode": "gradient",
        "orientation": "horizontal",
        "reduceOptions": {
          "calcs": ["lastNotNull"],
          "fields": "",
          "values": false
        }
      }
    },
    {
      "id": 7,
      "type": "timeseries",
      "title": "Backup Size Trend Over Time",
      "datasource": "${DS_PROMETHEUS}",
      "gridPos": { "h": 9, "w": 24, "x": 0, "y": 12 },
      "targets": [
        {
          "refId": "A",
          "expr": "k3s_backup_dir_size",
          "legendFormat": "{{type}}"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "unit": "bytes",
          "decimals": 2
        },
        "overrides": []
      },
      "options": {
        "legend": {
          "displayMode": "list",
          "placement": "bottom"
        },
        "tooltip": {
          "mode": "multi",
          "sort": "none"
        }
      }
    },
    {
      "id": 8,
      "type": "table",
      "title": "Backup Directory Detail (Size & Last MTime)",
      "datasource": "${DS_PROMETHEUS}",
      "gridPos": { "h": 9, "w": 24, "x": 0, "y": 21 },
      "targets": [
        {
          "refId": "A",
          "expr": "k3s_backup_dir_size",
          "legendFormat": "",
          "format": "table"
        },
        {
          "refId": "B",
          "expr": "k3s_backup_last_mtime",
          "legendFormat": "",
          "format": "table"
        }
      ],
      "fieldConfig": {
        "defaults": {
          "unit": "bytes",
          "decimals": 2
        },
        "overrides": []
      },
      "options": {
        "showHeader": true
      }
    }
  ],
  "schemaVersion": 39,
  "style": "dark",
  "tags": ["k3s", "backup", "truenas"],
  "templating": {
    "list": [
      {
        "name": "DS_PROMETHEUS",
        "type": "datasource",
        "query": "prometheus",
        "current": {
          "selected": true,
          "text": "Prometheus",
          "value": "Prometheus"
        },
        "label": "Prometheus datasource"
      }
    ]
  },
  "time": {
    "from": "now-24h",
    "to": "now"
  },
  "timepicker": {},
  "timezone": "",
  "title": "K3s Backup Verification",
  "uid": "k3s-backup-verification",
  "version": 1,
  "weekStart": ""
}

