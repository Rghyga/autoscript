#!/usr/bin/env bash
set -euo pipefail
source /usr/local/katsu-panel/lib/common.sh
source /usr/local/katsu-panel/lib/ui.sh
source /usr/local/katsu-panel/lib/xray.sh
source /usr/local/katsu-panel/lib/db.sh
proto="${KATSU_PROTO:-vmess}"
while true; do
  ui::clear
  ui::red_title "MENU ${proto^^}"
  ui::menu_item 1 "ADD ${proto^^}"
  ui::menu_item 2 "TRIAL ${proto^^}"
  ui::menu_item 3 'DELETE USER'
  ui::menu_item 4 'CHECK LOGIN'
  ui::menu_item 5 'RENEW USER'
  ui::menu_item 6 'CHANGE LIMIT'
  ui::menu_item 7 'USER LIST'
  ui::menu_item 8 'LOCK USER'
  ui::menu_item 9 'UNLOCK USER'
  ui::menu_item 0 'BACK'
  read -r -p 'Select option : ' opt
  case "$opt" in
    1)
      read -r -p 'Username: ' u; read -r -p 'Active days: ' d; read -r -p 'IP limit: ' l
      uuid=$(xray::create "$proto" "$u" "$d" "$l")
      exp=$(db::get_xray "$proto" "$u" | awk -F'\t' '{print $4}')
      echo; xray::print_account "$proto" "$u" "$uuid" "$exp" ;;
    2)
      read -r -p 'Trial minutes: ' m; res=$(xray::trial "$proto" "$m")
      u=$(cut -f1 <<<"$res"); uuid=$(cut -f2 <<<"$res")
      exp=$(db::get_xray "$proto" "$u" | awk -F'\t' '{print $4}')
      echo; xray::print_account "$proto" "$u" "$uuid" "$exp" ;;
    3) read -r -p 'Username: ' u; xray::delete "$proto" "$u" ;;
    4)
      ui::red_title "CHECK LOGIN ${proto^^}"
      printf '%-18s %-10s\n' 'Username' 'Online IP'
      while IFS=$'\t' read -r p u uuid e l s c; do [[ "$p" == "$proto" ]] && printf '%-18s %-10s\n' "$u" "$(xray::online_count "$u")"; done < <(db::list_xray)
      ;;
    5) read -r -p 'Username: ' u; read -r -p 'Extend days: ' d; xray::renew "$proto" "$u" "$d" ;;
    6) read -r -p 'Username: ' u; read -r -p 'New limit: ' l; xray::set_iplimit "$proto" "$u" "$l" ;;
    7)
      ui::red_title "USER ${proto^^}"
      printf '%-18s %-38s %-14s %-8s %-10s\n' 'Username' 'Credential' 'Expired' 'Limit' 'Status'
      while IFS=$'\t' read -r p u uuid e l s c; do [[ "$p" == "$proto" ]] && printf '%-18s %-38s %-14s %-8s %-10s\n' "$u" "$uuid" "$e" "$l" "$s"; done < <(db::list_xray)
      ;;
    8) read -r -p 'Username: ' u; xray::suspend "$proto" "$u" manual ;;
    9) read -r -p 'Username: ' u; xray::unsuspend "$proto" "$u" ;;
    0) exit 0 ;;
  esac
  ui::pause
done
