#!/usr/bin/env bash
set -euo pipefail
source /usr/local/katsu-panel/lib/common.sh
ensure_root
domain=$(read_domain); email=$(read_email)
[[ -n "$domain" ]] || { echo 'domain not set' >&2; exit 1; }
bash /usr/local/katsu-panel/scripts/issue-cert.sh "$domain" "$email"
bash /usr/local/katsu-panel/scripts/configure-nginx.sh "$domain" tls
xray_restart
