#!/usr/bin/env bash
set -euo pipefail
source /usr/local/katsu-panel/lib/common.sh

xray_meta_file() { printf '%s/%s/%s.json\n' "$KATSU_XRAY_USERS" "$1" "$2"; }
ssh_meta_file() { printf '%s/%s.json\n' "$KATSU_SSH_USERS" "$1"; }

xray_cache_rebuild() {
  : > "$KATSU_DB/xray.db"
  local proto file user uuid exp limit status created
  for proto in vmess vless trojan; do
    for file in "$KATSU_XRAY_USERS/$proto"/*.json; do
      [[ -e "$file" ]] || continue
      user=$(jq -r '.username' "$file")
      uuid=$(jq -r '.credential' "$file")
      exp=$(jq -r '.expire' "$file")
      limit=$(jq -r '.ip_limit' "$file")
      status=$(jq -r '.status' "$file")
      created=$(jq -r '.created_at' "$file")
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$proto" "$user" "$uuid" "$exp" "$limit" "$status" "$created" >> "$KATSU_DB/xray.db"
    done
  done
  sort -o "$KATSU_DB/xray.db" "$KATSU_DB/xray.db"
}

ssh_cache_rebuild() {
  : > "$KATSU_DB/ssh.db"
  local file u exp limit status created note
  for file in "$KATSU_SSH_USERS"/*.json; do
    [[ -e "$file" ]] || continue
    u=$(jq -r '.username' "$file")
    exp=$(jq -r '.expire' "$file")
    limit=$(jq -r '.ip_limit' "$file")
    status=$(jq -r '.status' "$file")
    created=$(jq -r '.created_at' "$file")
    note=$(jq -r '.note' "$file")
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$u" "$exp" "$limit" "$status" "$created" "$note" >> "$KATSU_DB/ssh.db"
  done
  sort -o "$KATSU_DB/ssh.db" "$KATSU_DB/ssh.db"
}

db::upsert_ssh() {
  local u="$1" exp="$2" limit="$3" status="$4" note="${5:-manual}" now file
  now=$(date -u +%FT%TZ)
  file=$(ssh_meta_file "$u")
  jq -n --arg username "$u" --arg expire "$exp" --argjson ip_limit "$limit" --arg status "$status" --arg created_at "$now" --arg note "$note" \
    '{username:$username,expire:$expire,ip_limit:$ip_limit,status:$status,created_at:$created_at,note:$note}' > "$file"
  ssh_cache_rebuild
}

db::delete_ssh() {
  local u="$1"
  rm -f "$(ssh_meta_file "$u")"
  ssh_cache_rebuild
}

db::get_ssh() { ssh_cache_rebuild; awk -F'\t' -v u="$1" '$1==u{print; exit}' "$KATSU_DB/ssh.db"; }
db::list_ssh() { ssh_cache_rebuild; sort "$KATSU_DB/ssh.db"; }

db::upsert_xray() {
  local proto="$1" u="$2" credential="$3" exp="$4" limit="$5" status="$6" now file
  now=$(date -u +%FT%TZ)
  file=$(xray_meta_file "$proto" "$u")
  mkdir -p "$(dirname "$file")"
  jq -n \
    --arg protocol "$proto" \
    --arg username "$u" \
    --arg credential "$credential" \
    --arg expire "$exp" \
    --argjson ip_limit "$limit" \
    --arg status "$status" \
    --arg created_at "$now" \
    '{protocol:$protocol,username:$username,credential:$credential,expire:$expire,ip_limit:$ip_limit,status:$status,created_at:$created_at}' > "$file"
  xray_cache_rebuild
}

db::delete_xray() {
  local proto="$1" u="$2"
  rm -f "$(xray_meta_file "$proto" "$u")"
  xray_cache_rebuild
}

db::get_xray() {
  local proto="$1" u="$2" file
  file=$(xray_meta_file "$proto" "$u")
  [[ -f "$file" ]] || return 0
  jq -r '[.protocol,.username,.credential,.expire,(.ip_limit|tostring),.status,.created_at] | @tsv' "$file"
}

db::list_xray() { xray_cache_rebuild; sort "$KATSU_DB/xray.db"; }
xray_meta_exists() { [[ -f "$(xray_meta_file "$1" "$2")" ]]; }
