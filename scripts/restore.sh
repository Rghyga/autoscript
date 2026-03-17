#!/usr/bin/env bash
set -euo pipefail
source /usr/local/katsu-panel/lib/common.sh
source /usr/local/katsu-panel/lib/db.sh
source /usr/local/katsu-panel/lib/ssh.sh
ensure_root
archive="${1:-}"
[[ -f "$archive" ]] || { echo "usage: restore.sh /path/to/backup.tar.gz" >&2; exit 1; }
tar -xzf "$archive" -C /
# rebuild SSH users from logs
if [[ -d /var/log/create/ssh ]]; then
  for f in /var/log/create/ssh/*.log; do
    [[ -f "$f" ]] || continue
    user=$(awk -F': ' '/Username/{print $2}' "$f" | head -n1)
    pass=$(awk -F': ' '/Password/{print $2}' "$f" | head -n1)
    exp=$(awk -F': ' '/Expired/{print $2}' "$f" | head -n1)
    limit=$(awk -F': ' '/Limit IP/{print $2}' "$f" | head -n1)
    [[ -n "$user" ]] || continue
    if ! id "$user" >/dev/null 2>&1; then
      useradd -M -N -s /usr/sbin/nologin -p "$(ssh::password_hash "${pass:-1}")" "$user"
    fi
    [[ -n "$exp" && "$exp" != "never" ]] && usermod -e "$exp" "$user" || true
    echo "${limit:-1}" > "$KATSU_STATE/iplimits/ssh/$user"
    echo "${limit:-1}" > "/etc/xray/limit/ip/ssh/$user"
  done
fi
systemctl daemon-reload
systemctl restart ssh || systemctl restart sshd || true
systemctl restart dropbear || true
systemctl restart nginx || true
systemctl restart xray || true
systemctl restart fail2ban || true
bash /usr/local/katsu-panel/scripts/apply-banner.sh || true
/usr/local/katsu-panel/scripts/self-check.sh || true
echo "Restore complete"
