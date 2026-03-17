#!/usr/bin/env bash
set -euo pipefail
source /usr/local/katsu-panel/lib/common.sh
ensure_root
stamp=$(date +%Y%m%d-%H%M%S)
out="/root/katsu-backup-${stamp}.tar.gz"
mkdir -p "$KATSU_WEBROOT/files"
tar -czf "$out" \
  /etc/katsu-panel \
  /var/log/create \
  /usr/local/etc/xray/config.json \
  /etc/nginx/sites-available/katsu-panel.conf \
  /etc/ssl/katsu-panel \
  /etc/issue.net \
  /etc/ssh/sshd_config.d \
  /etc/dropbear 2>/dev/null || true
cp -f "$out" "$KATSU_WEBROOT/files/$(basename "$out")"
echo "$out"
echo "https://$(read_domain)/files/$(basename "$out")"
