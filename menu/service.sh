#!/usr/bin/env bash
set -euo pipefail
source /usr/local/katsu-panel/lib/ui.sh
ui::clear
ui::red_title 'SERVICE STATUS'
ui::status 'SSH Service' ssh
ui::status 'Dropbear Service' dropbear
ui::status 'Nginx Service' nginx
ui::status 'Xray Service' xray
ui::status 'Fail2Ban Service' fail2ban
ui::status 'Cron Service' cron
ui::status 'VNStat Service' vnstat
ui::status 'SSH WS Service' katsu-sshws
ui::status 'IPLimit Service' katsu-iplimit
ui::status 'Expire Timer' katsu-expire.timer
ui::pause
