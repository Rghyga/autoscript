#!/usr/bin/env bash
set -euo pipefail
source /usr/local/katsu-panel/lib/common.sh
source /usr/local/katsu-panel/lib/ui.sh
source /usr/local/katsu-panel/lib/bandwidth.sh
source /usr/local/katsu-panel/lib/db.sh
init_dirs

human_uptime() { uptime -p 2>/dev/null || uptime; }
city() { curl -fsSL --max-time 5 https://ipinfo.io/city 2>/dev/null || echo '-'; }
isp() { curl -fsSL --max-time 5 https://ipinfo.io/org 2>/dev/null | sed 's/^[0-9]* //' || echo '-'; }
count_ssh() { db::list_ssh 2>/dev/null | awk 'NF{c++} END{print c+0}'; }
count_xray_proto() { db::list_xray 2>/dev/null | awk -F'\t' -v p="$1" '$1==p{c++} END{print c+0}'; }

svc_state() { local s=$(systemctl is-active "$1" 2>/dev/null || echo inactive); [[ $s == active ]] && echo Running || echo ${s^}; }

while true; do
  ui::clear
  ui::red_title 'SYSTEM INFORMATION'
  printf ' • %-14s = %s\n' 'System OS' "$(. /etc/os-release && echo "$PRETTY_NAME")"
  printf ' • %-14s = %s\n' 'Core CPU' "$(nproc 2>/dev/null || echo 1)"
  printf ' • %-14s = %s / %s\n' 'Server RAM' "$(free -m | awk '/Mem:/ {print $3" MB"}')" "$(free -m | awk '/Mem:/ {print $2" MB"}')"
  printf ' • %-14s = %s\n' 'Uptime' "$(human_uptime)"
  printf ' • %-14s = %s\n' 'City' "$(city)"
  printf ' • %-14s = %s\n' 'Domain' "$(read_domain)"
  printf ' • %-14s = %s\n' 'IP VPS' "$(public_ip)"
  printf ' • %-14s = %s\n' 'ISP' "$(isp)"
  printf ' • %-14s = %s\n' 'SSH Users' "$(count_ssh)"
  printf ' • %-14s = %s/%s/%s\n' 'Xray User' "$(count_xray_proto vmess)" "$(count_xray_proto vless)" "$(count_xray_proto trojan)"
  echo
  printf ' • %-14s = %s
' 'NGINX' "$(svc_state nginx)"
  printf ' • %-14s = %s
' 'XRAY' "$(svc_state xray)"
  printf ' • %-14s = %s
' 'SSH WS' "$(svc_state katsu-sshws)"
  printf ' • %-14s = %s
' 'DROPBEAR' "$(svc_state dropbear)"
  echo
  ui::menu_item 1 'SSH / OVPN'
  ui::menu_item 2 'VMESS / XRAY'
  ui::menu_item 3 'VLESS / XRAY'
  ui::menu_item 4 'TROJAN / XRAY'
  ui::menu_item 5 'BANDWIDTH'
  ui::menu_item 6 'BACKUP / RESTORE'
  ui::menu_item 7 'UPDATE SCRIPT'
  ui::menu_item 8 'SYSTEM'
  ui::menu_item 0 'EXIT'
  read -r -p 'Select Options [0-8]: ' opt
  case "$opt" in
    1) bash /usr/local/katsu-panel/menu/ssh.sh ;;
    2) KATSU_PROTO=vmess bash /usr/local/katsu-panel/menu/xray.sh ;;
    3) KATSU_PROTO=vless bash /usr/local/katsu-panel/menu/xray.sh ;;
    4) KATSU_PROTO=trojan bash /usr/local/katsu-panel/menu/xray.sh ;;
    5) bash /usr/local/katsu-panel/menu/bandwidth.sh ;;
    6) bash /usr/local/katsu-panel/menu/backup.sh ;;
    7) bash /usr/local/katsu-panel/scripts/update-panel.sh ;;
    8) bash /usr/local/katsu-panel/menu/system.sh ;;
    0) exit 0 ;;
  esac
done
