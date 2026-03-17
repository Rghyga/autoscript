#!/usr/bin/env bash
set -euo pipefail
source /usr/local/katsu-panel/lib/common.sh
ensure_root
read -r -p 'New domain: ' domain
[[ -n "$domain" ]] || exit 1
echo "$domain" > "$KATSU_DOMAIN_FILE"
cfg_set KATSU_DOMAIN "$domain"
bash /usr/local/katsu-panel/scripts/issue-cert.sh "$domain" "$(read_email)"
bash /usr/local/katsu-panel/scripts/configure-nginx.sh "$domain" tls
xray_restart
