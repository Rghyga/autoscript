#!/usr/bin/env bash
set -euo pipefail
source /usr/local/katsu-panel/lib/common.sh
source /usr/local/katsu-panel/lib/ssh.sh
source /usr/local/katsu-panel/lib/xray.sh
source /usr/local/katsu-panel/lib/db.sh
ensure_root
init_dirs

threshold_loops=3
sleep_sec=15

mkdir -p "$KATSU_RUNTIME/violations/ssh" "$KATSU_RUNTIME/violations/xray"

while true; do
  # SSH realtime kick and suspend
  while IFS=$'\t' read -r username exp limit status created note; do
    [[ -z "$username" ]] && continue
    [[ "$status" == "active" ]] || continue
    [[ -f "$KATSU_STATE/iplimits/ssh/$username" ]] || continue
    limit=$(cat "$KATSU_STATE/iplimits/ssh/$username" 2>/dev/null || echo 0)
    [[ "$limit" =~ ^[0-9]+$ ]] || limit=0
    (( limit > 0 )) || continue
    count=$(ssh::online_ip_count "$username" || echo 0)
    if (( count > limit )); then
      n=$(($(cat "$KATSU_RUNTIME/violations/ssh/$username" 2>/dev/null || echo 0) + 1))
      echo "$n" > "$KATSU_RUNTIME/violations/ssh/$username"
      pkill -KILL -u "$username" >/dev/null 2>&1 || true
      log WARN "SSH over-limit: user=$username online_ip=$count limit=$limit"
      if (( n >= threshold_loops )); then
        ssh::suspend "$username" sharing
        log WARN "SSH auto-suspend: user=$username"
        rm -f "$KATSU_RUNTIME/violations/ssh/$username"
      fi
    else
      rm -f "$KATSU_RUNTIME/violations/ssh/$username"
    fi
  done < <(db::list_ssh)

  # XRAY realtime suspend based on online stat count
  while IFS=$'\t' read -r proto username uuid exp limit status created; do
    [[ -z "$proto" ]] && continue
    [[ "$status" == "active" ]] || continue
    limit=$(cat "$KATSU_STATE/iplimits/xray/$proto/$username" 2>/dev/null || echo "$limit")
    [[ "$limit" =~ ^[0-9]+$ ]] || limit=0
    (( limit > 0 )) || continue
    count=$(xray::online_count "$username" || echo 0)
    if (( count > limit )); then
      n=$(($(cat "$KATSU_RUNTIME/violations/xray/${proto}__${username}" 2>/dev/null || echo 0) + 1))
      echo "$n" > "$KATSU_RUNTIME/violations/xray/${proto}__${username}"
      log WARN "XRAY over-limit: protocol=$proto user=$username online=$count limit=$limit"
      if (( n >= threshold_loops )); then
        xray::suspend "$proto" "$username" sharing
        log WARN "XRAY auto-suspend: protocol=$proto user=$username"
        rm -f "$KATSU_RUNTIME/violations/xray/${proto}__${username}"
      fi
    else
      rm -f "$KATSU_RUNTIME/violations/xray/${proto}__${username}"
    fi
  done < <(db::list_xray)

  sleep "$sleep_sec"
done
