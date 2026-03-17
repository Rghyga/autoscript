#!/usr/bin/env bash
set -euo pipefail
source /usr/local/katsu-panel/lib/common.sh
source /usr/local/katsu-panel/lib/ssh.sh
source /usr/local/katsu-panel/lib/xray.sh
source /usr/local/katsu-panel/lib/db.sh
ensure_root

now=$(date -u +%s)

while IFS=$'\t' read -r username exp limit status created note; do
  [[ -z "$username" ]] && continue
  [[ "$exp" == *T*Z ]] && exp_epoch=$(date -u -d "$exp" +%s) || exp_epoch=$(date -u -d "$exp 23:59:59" +%s)
  if (( exp_epoch <= now )); then
    log INFO "Deleting expired SSH user $username"
    ssh::delete "$username"
  fi
done < <(db::list_ssh)

while IFS=$'\t' read -r proto username uuid exp limit status created; do
  [[ -z "$proto" ]] && continue
  [[ "$exp" == *T*Z ]] && exp_epoch=$(date -u -d "$exp" +%s) || exp_epoch=$(date -u -d "$exp 23:59:59" +%s)
  if (( exp_epoch <= now )); then
    log INFO "Deleting expired XRAY user $proto/$username"
    xray::delete "$proto" "$username"
  fi
done < <(db::list_xray)
