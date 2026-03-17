#!/usr/bin/env bash
set -euo pipefail
source /usr/local/katsu-panel/lib/ui.sh

ui::clear
ui::title 'SUSPENDED ACCOUNTS'
echo 'SSH:'
ls -1 /etc/katsu-panel/state/suspended/ssh 2>/dev/null || true
ui::line
echo 'XRAY:'
ls -1 /etc/katsu-panel/state/suspended/xray 2>/dev/null || true
ui::pause
