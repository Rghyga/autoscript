#!/usr/bin/env bash
# shellcheck shell=bash
[[ $- == *i* ]] || return 0 2>/dev/null || exit 0
[[ -x /usr/bin/tput ]] || return 0 2>/dev/null || exit 0
clear 2>/dev/null || true

C0='\033[0m'; C1='\033[1;36m'; C2='\033[1;32m'; C3='\033[1;31m'; C5='\033[1;37m'; C8='\033[0;90m'
line() { printf '%b\n' "${C1}────────────────────────────────────────────────────────────${C0}"; }
kv() { printf '%-20s : %s\n' "$1" "$2"; }
service_status() {
  local svc="$1"
  if systemctl is-active --quiet "$svc" 2>/dev/null; then printf '%bACTIVE%b' "$C2" "$C0"; else printf '%bINACTIVE%b' "$C3" "$C0"; fi
}
public_ip() {
  curl -4fsSL --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I 2>/dev/null | awk '{print $1}'
}
read_domain() { [[ -f /etc/katsu-panel/domain ]] && cat /etc/katsu-panel/domain || echo '-'; }
count_files() { find "$1" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l; }
ssh_count() { find /etc/katsu-panel/users/ssh -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l; }
vmess_count() { count_files /etc/katsu-panel/users/xray/vmess; }
vless_count() { count_files /etc/katsu-panel/users/xray/vless; }
trojan_count() { count_files /etc/katsu-panel/users/xray/trojan; }

line
printf '%b\n' "${C5} KATSU PANEL ${C0}${C8}- welcome${C0}"
line
kv 'Hostname' "$(hostname 2>/dev/null)"
kv 'OS' "$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}")"
kv 'Kernel' "$(uname -r 2>/dev/null)"
kv 'Public IP' "$(public_ip)"
kv 'Domain' "$(read_domain)"
kv 'Uptime' "$(uptime -p 2>/dev/null || uptime)"
line
kv 'SSH Service' "$(service_status ssh || service_status sshd)"
kv 'XRAY Service' "$(service_status xray)"
kv 'NGINX Service' "$(service_status nginx)"
kv 'FAIL2BAN' "$(service_status fail2ban)"
line
kv 'SSH Users' "$(ssh_count)"
kv 'VMESS Users' "$(vmess_count)"
kv 'VLESS Users' "$(vless_count)"
kv 'TROJAN Users' "$(trojan_count)"
line
printf ' Commands             : menu | update | katsu-selfcheck\n'
line
