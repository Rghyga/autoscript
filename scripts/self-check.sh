#!/usr/bin/env bash
set -euo pipefail
source /usr/local/katsu-panel/lib/common.sh
ensure_root
strict=0
[[ "${1:-}" == "--strict" ]] && strict=1
fails=0
check() {
  local desc="$1" cmd="$2"
  if bash -lc "$cmd" >/dev/null 2>&1; then printf '[OK] %s\n' "$desc"; else printf '[FAIL] %s\n' "$desc"; fails=$((fails+1)); fi
}
check 'Project source exists' '[[ -d /usr/local/katsu-panel ]]'
check 'Config dir exists' '[[ -d /etc/katsu-panel ]]'
check 'SSH metadata dir exists' '[[ -d /etc/katsu-panel/users/ssh ]]'
check 'XRAY metadata dir exists' '[[ -d /etc/katsu-panel/users/xray ]]'
check 'Create log dirs exist' '[[ -d /var/log/create/ssh && -d /var/log/create/xray/ws && -d /var/log/create/xray/grpc ]]'
check 'Legacy limit dirs exist' '[[ -d /etc/xray/limit/ip/ssh && -d /etc/xray/limit/ip/xray/ws && -d /etc/xray/limit/ip/xray/grpc ]]'
check 'Xray config exists' '[[ -f /usr/local/etc/xray/config.json ]]'
check 'Xray config valid JSON' 'jq empty /usr/local/etc/xray/config.json'
check 'Xray config passes xray test' 'xray run -test -config /usr/local/etc/xray/config.json'
check 'Nginx config valid' 'nginx -t'
check 'Nginx route file exists' '[[ -s /etc/nginx/conf.d/katsu.conf || -s /etc/nginx/sites-available/katsu-panel.conf ]]'
check 'Port 80 listen' 'ss -ltn | grep -q ":80 "'
check 'Port 443 listen' 'ss -ltn | grep -q ":443 "'
check 'SSH WS internal port listen' 'ss -ltn | grep -q ":2082 "'
check 'VMESS WS internal port listen' 'ss -ltn | grep -q ":10001 "'
check 'Certificate fullchain exists' '[[ -f /etc/ssl/katsu-panel/fullchain.cer ]]'
check 'Certificate private key exists' '[[ -f /etc/ssl/katsu-panel/private.key ]]'
check 'Certificate parseable' 'openssl x509 -in /etc/ssl/katsu-panel/fullchain.cer -noout -subject'
check 'SSH service active' 'systemctl is-active --quiet ssh || systemctl is-active --quiet sshd'
check 'Dropbear service active' 'systemctl is-active --quiet dropbear'
check 'SSH WS service active' 'systemctl is-active --quiet katsu-sshws'
check 'XRAY service active' 'systemctl is-active --quiet xray'
check 'NGINX service active' 'systemctl is-active --quiet nginx'
check 'FAIL2BAN service active' 'systemctl is-active --quiet fail2ban'
check 'Realtime IP limit service active' 'systemctl is-active --quiet katsu-iplimit'
check 'Expiry timer active' 'systemctl is-active --quiet katsu-expire.timer'
check 'ACME installed' '[[ -x /root/.acme.sh/acme.sh ]]'
check 'Menu launcher exists' 'command -v menu >/dev/null 2>&1'
(( strict == 1 && fails > 0 )) && exit 1 || exit 0
