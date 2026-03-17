#!/usr/bin/env bash
set -euo pipefail
source /usr/local/katsu-panel/lib/common.sh
source /usr/local/katsu-panel/lib/ui.sh
source /usr/local/katsu-panel/lib/ssh.sh
source /usr/local/katsu-panel/lib/db.sh
while true; do
  ui::clear
  ui::red_title 'MENU SSH/OVPN'
  ui::menu_item 1 'ADD SSH'
  ui::menu_item 2 'TRIAL SSH'
  ui::menu_item 3 'DELETE USER'
  ui::menu_item 4 'CHECK LOGIN'
  ui::menu_item 5 'RENEW USER'
  ui::menu_item 6 'MEMBER SSH'
  ui::menu_item 7 'CHANGE LIMIT'
  ui::menu_item 8 'CHANGE BANNER'
  ui::menu_item 9 'LOCK SSH'
  ui::menu_item 10 'UNLOCK SSH'
  ui::menu_item 0 'BACK TO MAIN MENU'
  read -r -p 'Select option : ' opt
  case "$opt" in
    1)
      read -r -p 'Username: ' u; read -r -p 'Password: ' p; read -r -p 'Active days: ' d; read -r -p 'IP limit: ' l
      ssh::create "$u" "$p" "$d" "$l"
      ;;
    2)
      read -r -p 'Trial minutes: ' m
      cred=$(ssh::trial "$m")
      ui::ok "Trial created: $cred"
      ;;
    3) read -r -p 'Username: ' u; ssh::delete "$u"; ui::ok 'Deleted';;
    4)
      ui::red_title 'CHECK LOGIN SSH'
      printf '%-18s %-10s\n' 'Username' 'Unique IP'
      while IFS=$'\t' read -r u e l s c n; do [[ -n "$u" ]] && printf '%-18s %-10s\n' "$u" "$(ssh::online_ip_count "$u")"; done < <(db::list_ssh)
      ;;
    5) read -r -p 'Username: ' u; read -r -p 'Extend days: ' d; ssh::renew "$u" "$d" ;;
    6)
      ui::red_title 'MEMBER SSH'
      printf '%-18s %-18s %-8s %-10s\n' 'Username' 'Expired' 'Limit' 'Status'
      while IFS=$'\t' read -r u e l s c n; do [[ -n "$u" ]] && printf '%-18s %-18s %-8s %-10s\n' "$u" "$e" "$l" "$s"; done < <(db::list_ssh)
      ;;
    7) read -r -p 'Username: ' u; read -r -p 'New limit: ' l; ssh::set_iplimit "$u" "$l"; ui::ok 'Limit updated';;
    8) bash /usr/local/katsu-panel/scripts/change-banner.sh ;;
    9) read -r -p 'Username: ' u; ssh::suspend "$u" manual; ui::ok 'User locked';;
    10) read -r -p 'Username: ' u; ssh::unsuspend "$u"; ui::ok 'User unlocked';;
    0) exit 0 ;;
  esac
  ui::pause
done
