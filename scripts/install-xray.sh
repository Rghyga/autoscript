#!/usr/bin/env bash
set -euo pipefail
source /usr/local/katsu-panel/lib/common.sh
ensure_root

if ! have xray; then
  bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install -u root --without-geodata
fi
mkdir -p /usr/local/etc/xray /etc/xray /var/log/xray
cp /usr/local/katsu-panel/templates/xray-config.json "$KATSU_XRAY_CFG"
ln -sf "$KATSU_XRAY_CFG" /etc/xray/config.json
chmod 640 "$KATSU_XRAY_CFG"
chown root:root "$KATSU_XRAY_CFG"
systemctl enable xray
xray run -test -config "$KATSU_XRAY_CFG"
systemctl restart xray
