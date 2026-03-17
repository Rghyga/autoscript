#!/usr/bin/env bash
set -euo pipefail
source /usr/local/katsu-panel/lib/common.sh
ensure_root
src="${1:-/usr/local/katsu-panel/config/banner.default}"
[[ -f "$src" ]] || { echo "banner source not found" >&2; exit 1; }
mkdir -p /etc/ssh/sshd_config.d
cp "$src" /etc/issue.net
if ! grep -q '^Banner /etc/issue.net$' /etc/ssh/sshd_config 2>/dev/null && ! grep -Rqs '^Banner /etc/issue.net$' /etc/ssh/sshd_config.d; then
  echo 'Banner /etc/issue.net' > /etc/ssh/sshd_config.d/katsu-banner.conf
fi
systemctl restart ssh || systemctl restart sshd || true
