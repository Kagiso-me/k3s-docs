#!/bin/bash
# -------------------------------------------------
# Generate Prometheus Metrics for K3s Backups
# -------------------------------------------------
# Tracks:
#   - Last modification time per backup type
#   - Backup directory sizes
#   - Overall backup success/failure from logs
# -------------------------------------------------

# Config
OUT="/var/lib/node_exporter/textfile_collector/k3s_backup.prom"
BACKUP_ROOT="/mnt/backup-tera/k3s"
LOG_FILE="/var/log/k3s-backups.log"

# Helper functions
mtime() { stat -c %Y "$1" 2>/dev/null || echo 0; }
du_size() { du -sb "$1" 2>/dev/null | awk '{print $1}'; }

# -------------------------------------------------
# Write Metrics
# -------------------------------------------------
{
echo "# HELP k3s_backup_last_mtime Last backup file modification times (Unix timestamp)"
echo "# TYPE k3s_backup_last_mtime gauge"
echo "k3s_backup_last_mtime{type=\"manifests\"} $(mtime $BACKUP_ROOT/manifests)"
echo "k3s_backup_last_mtime{type=\"node_jaime\"} $(mtime $BACKUP_ROOT/nodes/jaime)"
echo "k3s_backup_last_mtime{type=\"node_tyrion\"} $(mtime $BACKUP_ROOT/nodes/tyrion)"
echo "k3s_backup_last_mtime{type=\"pv_backup\"} $(mtime $BACKUP_ROOT/pv)"
echo ""

echo "# HELP k3s_backup_dir_size Backup directory sizes in bytes"
echo "# TYPE k3s_backup_dir_size gauge"
echo "k3s_backup_dir_size{type=\"manifests\"} $(du_size $BACKUP_ROOT/manifests)"
echo "k3s_backup_dir_size{type=\"nodes\"} $(du_size $BACKUP_ROOT/nodes)"
echo "k3s_backup_dir_size{type=\"pv_backup\"} $(du_size $BACKUP_ROOT/pv)"
echo ""

echo "# HELP k3s_backup_status Overall backup success/failure (1=success, 0=failure)"
echo "# TYPE k3s_backup_status gauge"
if tail -n 50 "$LOG_FILE" 2>/dev/null | grep -q -i "error"; then
    echo "k3s_backup_status 0"
else
    echo "k3s_backup_status 1"
fi
} > "$OUT"
