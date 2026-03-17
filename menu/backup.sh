#!/usr/bin/env bash
set -euo pipefail
source /usr/local/katsu-panel/lib/ui.sh
while true; do
  ui::clear
  ui::red_title 'MENU BACKUP VPS'
  ui::menu_item 1 'Backup VPS Data'
  ui::menu_item 2 'Restore VPS Data'
  ui::menu_item 3 'Auto backup VPS Data'
  ui::menu_item 4 'Reset Default Banner'
  ui::menu_item 0 'Back To Menu'
  read -r -p 'Select menu [0-4] : ' opt
  case "$opt" in
    1) bash /usr/local/katsu-panel/scripts/backup.sh ;;
    2) read -r -p 'Local backup file path: ' f; bash /usr/local/katsu-panel/scripts/restore.sh "$f" ;;
    3) read -r -p 'Daily backup HH:MM (UTC): ' t; h=${t%:*}; m=${t#*:}; echo "$m $h * * * root /usr/local/katsu-panel/scripts/backup.sh >/var/log/katsu-panel/autobackup.log 2>&1" > /etc/cron.d/katsu-autobackup; ui::ok 'Autobackup configured' ;;
    4) bash /usr/local/katsu-panel/scripts/reset-banner.sh ;;
    0) exit 0 ;;
  esac
  ui::pause
done
