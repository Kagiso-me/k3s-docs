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