#!/usr/bin/env bash
set -euo pipefail
source /usr/local/katsu-panel/lib/ui.sh
ssh_unit() { systemctl list-unit-files ssh.service >/dev/null 2>&1 && echo ssh || echo sshd; }
while true; do
  ui::clear
  ui::red_title 'MENU SYSTEM'
  ui::menu_item 1 'CEK SERVICE'
  ui::menu_item 2 'RESTART SERVICE'
  ui::menu_item 3 'CHANGE BANNER'
  ui::menu_item 4 'CHANGE DOMAIN'
  ui::menu_item 5 'FIX SSL'
  ui::menu_item 6 'CLEAR LOG'
  ui::menu_item 7 'CLEAR CACHE'
  ui::menu_item 8 'BACKUP/RESTORE'
  ui::menu_item 9 'RUN SELF CHECK'
  ui::menu_item 10 'AUTO REBOOT'
  ui::menu_item 0 'BACK'
  read -r -p 'Select From Options [0-10] : ' opt
  case "$opt" in
    1) bash /usr/local/katsu-panel/menu/service.sh ;;
    2)
      systemctl restart "$(ssh_unit)" nginx xray fail2ban dropbear katsu-sshws || true
      ui::ok 'Core services restarted'
      ;;
    3) bash /usr/local/katsu-panel/scripts/change-banner.sh ;;
    4) bash /usr/local/katsu-panel/scripts/change-domain.sh ;;
    5) bash /usr/local/katsu-panel/scripts/fix-ssl.sh ;;
    6) find /var/log -type f -name '*.log' -exec sh -c ': > "$1"' _ {} \; ; ui::ok 'Logs cleared' ;;
    7) rm -rf /var/cache/apt/archives/* /tmp/* 2>/dev/null || true; ui::ok 'Cache cleared' ;;
    8) bash /usr/local/katsu-panel/menu/backup.sh ;;
    9) bash /usr/local/katsu-panel/scripts/self-check.sh ;;
    10) read -r -p 'Daily reboot HH:MM (UTC): ' t; h=${t%:*}; m=${t#*:}; echo "$m $h * * * root /sbin/reboot" > /etc/cron.d/katsu-autoreboot; ui::ok 'Auto reboot configured' ;;
    0) exit 0 ;;
  esac
  ui::pause
done
