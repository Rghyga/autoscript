#!/usr/bin/env bash
set -euo pipefail
source /usr/local/katsu-panel/lib/common.sh

svc::restart_core() {
  systemctl restart ssh nginx xray fail2ban
}

svc::status_line() {
  local svc="$1"
  printf '%s\t%s\n' "$svc" "$(service_state "$svc")"
}
