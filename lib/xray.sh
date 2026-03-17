#!/usr/bin/env bash
set -euo pipefail
source /usr/local/katsu-panel/lib/common.sh
source /usr/local/katsu-panel/lib/db.sh
source /usr/local/katsu-panel/lib/ui.sh

xray::ensure_config() { [[ -f "$KATSU_XRAY_CFG" ]] || { echo "Xray config missing" >&2; return 1; }; }
xray::log_file() { printf '%s/xray/%s/%s.log\n' "$KATSU_CREATE_LOG" "$1" "$2"; }
xray::limit_file() { printf '%s/iplimits/xray/%s/%s\n' "$KATSU_STATE" "$1" "$2"; }
xray::share_file() { printf '%s/files/%s-%s.txt\n' "$KATSU_WEBROOT" "$1" "$2"; }

xray::client_json() {
  local protocol="$1" credential="$2" username="$3"
  case "$protocol" in
    vmess) jq -cn --arg id "$credential" --arg email "$username" '{id:$id,alterId:0,email:$email}' ;;
    vless) jq -cn --arg id "$credential" --arg email "$username" '{id:$id,email:$email}' ;;
    trojan) jq -cn --arg password "$credential" --arg email "$username" '{password:$password,email:$email}' ;;
    *) return 1 ;;
  esac
}

xray::validate_protocol() { case "$1" in vmess|vless|trojan) return 0 ;; *) echo "Unknown protocol: $1" >&2; return 1;; esac; }

xray::user_exists_in_config() {
  local username="$1"
  jq -e --arg u "$username" 'any(.inbounds[]?; any(.settings.clients[]?; .email == $u))' "$KATSU_XRAY_CFG" >/dev/null 2>&1
}

xray::assert_creatable() {
  local protocol="$1" username="$2"
  xray::validate_protocol "$protocol"
  valid_username "$username" || { echo "Invalid username" >&2; return 1; }
  if xray_meta_exists "$protocol" "$username"; then echo "User ${protocol}/${username} already exists" >&2; return 1; fi
  if xray::user_exists_in_config "$username"; then echo "Email/username $username already exists in Xray config" >&2; return 1; fi
}

xray::ws_path() {
  case "$1" in
    vmess) echo "/vmess" ;;
    vless) echo "/vless" ;;
    trojan) echo "/trojan" ;;
  esac
}

xray::grpc_service() {
  case "$1" in
    vmess) echo "vmess-grpc" ;;
    vless) echo "vless-grpc" ;;
    trojan) echo "trojan-grpc" ;;
  esac
}

xray::geo_city() { curl -fsSL --max-time 6 ipinfo.io/city 2>/dev/null || echo "Unknown"; }
xray::geo_isp() { curl -fsSL --max-time 6 ipinfo.io/org 2>/dev/null | sed 's/^AS[0-9]\+ //' || echo "Unknown"; }

xray::vmess_json_link() {
  local username="$1" credential="$2" port="$3" net="$4" path="$5" host="$6" tls="$7" type="$8"
  jq -cn \
    --arg v "2" \
    --arg ps "$username" \
    --arg add "$host" \
    --arg port "$port" \
    --arg id "$credential" \
    --arg aid "0" \
    --arg net "$net" \
    --arg path "$path" \
    --arg type "$type" \
    --arg host "$host" \
    --arg tls "$tls" \
    '{v:$v,ps:$ps,add:$add,port:$port,id:$id,aid:$aid,net:$net,path:$path,type:$type,host:$host,tls:$tls}' | base64 -w0 | sed 's#^#vmess://#'
}

xray::vmess_ws_tls_link() { local u="$1" credential="$2" d; d=$(read_domain); xray::vmess_json_link "$u" "$credential" "443" "ws" "$(xray::ws_path vmess)" "$d" "tls" "none"; }
xray::vmess_ws_ntls_link() { local u="$1" credential="$2" d; d=$(read_domain); xray::vmess_json_link "$u" "$credential" "80" "ws" "$(xray::ws_path vmess)" "$d" "none" "none"; }
xray::vmess_grpc_link() { local u="$1" credential="$2" d; d=$(read_domain); xray::vmess_json_link "$u" "$credential" "443" "grpc" "$(xray::grpc_service vmess)" "$d" "tls" "none"; }
xray::vless_ws_link() { local u="$1" credential="$2" d; d=$(read_domain); echo "vless://${credential}@${d}:443?encryption=none&security=tls&type=ws&host=${d}&path=%2F$(basename "$(xray::ws_path vless)")#${u}"; }
xray::vless_grpc_link() { local u="$1" credential="$2" d; d=$(read_domain); echo "vless://${credential}@${d}:443?encryption=none&security=tls&type=grpc&serviceName=$(xray::grpc_service vless)&mode=gun#${u}"; }
xray::trojan_ws_link() { local u="$1" credential="$2" d; d=$(read_domain); echo "trojan://${credential}@${d}:443?security=tls&type=ws&host=${d}&path=%2F$(basename "$(xray::ws_path trojan)")#${u}"; }
xray::trojan_grpc_link() { local u="$1" credential="$2" d; d=$(read_domain); echo "trojan://${credential}@${d}:443?security=tls&type=grpc&serviceName=$(xray::grpc_service trojan)&mode=gun#${u}"; }
xray::link() { local p="$1" t="$2" u="$3" c="$4"; case "${p}-${t}" in vmess-ws) xray::vmess_ws_tls_link "$u" "$c";; vmess-ntls) xray::vmess_ws_ntls_link "$u" "$c";; vmess-grpc) xray::vmess_grpc_link "$u" "$c";; vless-ws) xray::vless_ws_link "$u" "$c";; vless-grpc) xray::vless_grpc_link "$u" "$c";; trojan-ws) xray::trojan_ws_link "$u" "$c";; trojan-grpc) xray::trojan_grpc_link "$u" "$c";; esac; }

xray::write_share_file() {
  local protocol="$1" username="$2" credential="$3" exp="$4" domain city isp path grpc_service file
  mkdir -p "$KATSU_WEBROOT/files"
  domain=$(read_domain)
  city=$(xray::geo_city)
  isp=$(xray::geo_isp)
  path=$(xray::ws_path "$protocol")
  grpc_service=$(xray::grpc_service "$protocol")
  file=$(xray::share_file "$protocol" "$username")
  case "$protocol" in
    vmess)
      cat > "$file" <<TXT
┌─────────────────────────────────────────────────────────┐
                  PREMIUM VMESS ACCOUNT
└─────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────┐
│  User          : $username
│  ISP           : $isp
│  City          : $city
│  Domain        : $domain
│  Port TLS      : 443
│  Port NTLS     : 80
│  Port gRPC     : 443
│  UUID          : $credential
│  alterId       : 0
│  Security      : auto
│  Network       : ws
│  Path          : $path
│  Path Support  : http://bug$path
│  ServiceName   : $grpc_service
├─────────────────────────────────────────────────────────┤
│  Link Websocket TLS :
│  $(xray::vmess_ws_tls_link "$username" "$credential")
├─────────────────────────────────────────────────────────┤
│  Link Websocket NTLS :
│  $(xray::vmess_ws_ntls_link "$username" "$credential")
├─────────────────────────────────────────────────────────┤
│  Link gRPC :
│  $(xray::vmess_grpc_link "$username" "$credential")
├─────────────────────────────────────────────────────────┤
│  Format Openclash    : http://$domain:81/vmess-$username.txt
├─────────────────────────────────────────────────────────┤
│  Expired Akun       : $exp
└─────────────────────────────────────────────────────────┘
TXT
      ;;
    vless)
      cat > "$file" <<TXT
User          : $username
Domain        : $domain
Port TLS      : 443
Port gRPC     : 443
UUID          : $credential
Path          : $path
ServiceName   : $grpc_service
Link WS       : $(xray::vless_ws_link "$username" "$credential")
Link gRPC     : $(xray::vless_grpc_link "$username" "$credential")
Expired       : $exp
TXT
      ;;
    trojan)
      cat > "$file" <<TXT
User          : $username
Domain        : $domain
Port TLS      : 443
Port gRPC     : 443
Password      : $credential
Path          : $path
ServiceName   : $grpc_service
Link WS       : $(xray::trojan_ws_link "$username" "$credential")
Link gRPC     : $(xray::trojan_grpc_link "$username" "$credential")
Expired       : $exp
TXT
      ;;
  esac
}

xray::write_logs() {
  local protocol="$1" username="$2" credential="$3" exp="$4" limit="$5"
  local domain wsfile grpcfile
  domain=$(read_domain)
  wsfile=$(xray::log_file ws "$username")
  grpcfile=$(xray::log_file grpc "$username")
  mkdir -p "$(dirname "$wsfile")" "$(dirname "$grpcfile")"
  cat > "$wsfile" <<LOG
Protocol      : $protocol
Username      : $username
Credential    : $credential
Expired       : $exp
Limit IP      : $limit
Domain        : $domain
Transport     : ws
Path          : $(xray::ws_path "$protocol")
Link TLS      : $(xray::link "$protocol" ws "$username" "$credential")
LOG
  cat > "$grpcfile" <<LOG
Protocol      : $protocol
Username      : $username
Credential    : $credential
Expired       : $exp
Limit IP      : $limit
Domain        : $domain
Transport     : grpc
ServiceName   : $(xray::grpc_service "$protocol")
Link          : $(xray::link "$protocol" grpc "$username" "$credential")
LOG
  xray::write_share_file "$protocol" "$username" "$credential" "$exp"
}

xray::add_client() {
  local protocol="$1" username="$2" credential="$3"
  xray::ensure_config
  local client filter
  client=$(xray::client_json "$protocol" "$credential" "$username")
  case "$protocol" in
    vmess) filter='(.inbounds[] | select(.tag=="vmess-ws" or .tag=="vmess-grpc") | .settings.clients) += [$client]' ;;
    vless) filter='(.inbounds[] | select(.tag=="vless-ws" or .tag=="vless-grpc") | .settings.clients) += [$client]' ;;
    trojan) filter='(.inbounds[] | select(.tag=="trojan-ws" or .tag=="trojan-grpc") | .settings.clients) += [$client]' ;;
  esac
  jq --argjson client "$client" "$filter" "$KATSU_XRAY_CFG" > "$KATSU_XRAY_CFG.tmp"
  mv "$KATSU_XRAY_CFG.tmp" "$KATSU_XRAY_CFG"
  xray run -test -config "$KATSU_XRAY_CFG" >/dev/null
}

xray::del_client() {
  local protocol="$1" username="$2"
  xray::ensure_config
  local filter
  case "$protocol" in
    vmess) filter='(.inbounds[] | select(.tag=="vmess-ws" or .tag=="vmess-grpc") | .settings.clients) |= map(select(.email != $u))' ;;
    vless) filter='(.inbounds[] | select(.tag=="vless-ws" or .tag=="vless-grpc") | .settings.clients) |= map(select(.email != $u))' ;;
    trojan) filter='(.inbounds[] | select(.tag=="trojan-ws" or .tag=="trojan-grpc") | .settings.clients) |= map(select(.email != $u))' ;;
  esac
  jq --arg u "$username" "$filter" "$KATSU_XRAY_CFG" > "$KATSU_XRAY_CFG.tmp"
  mv "$KATSU_XRAY_CFG.tmp" "$KATSU_XRAY_CFG"
  xray run -test -config "$KATSU_XRAY_CFG" >/dev/null
}

xray::create() {
  local protocol="$1" username="$2" days="$3" ip_limit="$4" credential exp
  xray::assert_creatable "$protocol" "$username"
  credential=$(uuid_new)
  exp=$(expire_date_days "$days")
  xray::add_client "$protocol" "$username" "$credential"
  mkdir -p "$(dirname "$(xray::limit_file "$protocol" "$username")")"
  echo "$ip_limit" > "$(xray::limit_file "$protocol" "$username")"
  echo "$ip_limit" > "/etc/xray/limit/ip/xray/ws/$username"
  echo "$ip_limit" > "/etc/xray/limit/ip/xray/grpc/$username"
  db::upsert_xray "$protocol" "$username" "$credential" "$exp" "$ip_limit" active
  xray::write_logs "$protocol" "$username" "$credential" "$exp" "$ip_limit"
  xray_restart
  echo "$credential"
}

xray::delete() {
  local protocol="$1" username="$2"
  xray::validate_protocol "$protocol"
  xray::del_client "$protocol" "$username"
  rm -f "$(xray::limit_file "$protocol" "$username")" "$KATSU_STATE/suspended/xray/${protocol}__${username}" "/etc/xray/limit/ip/xray/ws/$username" "/etc/xray/limit/ip/xray/grpc/$username" "$(xray::log_file ws "$username")" "$(xray::log_file grpc "$username")" "$(xray::share_file "$protocol" "$username")"
  db::delete_xray "$protocol" "$username"
  xray_restart
}

xray::renew() {
  local protocol="$1" username="$2" days="$3" row exp credential limit status created
  row=$(db::get_xray "$protocol" "$username")
  [[ -n "$row" ]] || { echo "Xray user not found" >&2; return 1; }
  credential=$(awk -F'\t' '{print $3}' <<<"$row")
  exp=$(awk -F'\t' '{print $4}' <<<"$row")
  limit=$(awk -F'\t' '{print $5}' <<<"$row")
  status=$(awk -F'\t' '{print $6}' <<<"$row")
  created=$(awk -F'\t' '{print $7}' <<<"$row")
  exp=$(date -u -d "$exp + $days day" +%F)
  db::upsert_xray "$protocol" "$username" "$credential" "$exp" "$limit" "$status"
  local file; file=$(xray_meta_file "$protocol" "$username")
  jq --arg created "$created" '.created_at = $created' "$file" > "$file.tmp" && mv "$file.tmp" "$file"
  xray::write_logs "$protocol" "$username" "$credential" "$exp" "$limit"
  xray_cache_rebuild
}

xray::trial() {
  local protocol="$1" mins="$2" username credential exp run_at
  xray::validate_protocol "$protocol"
  while :; do
    username="trial$(random_string 4)"
    if ! xray_meta_exists "$protocol" "$username" && ! xray::user_exists_in_config "$username"; then break; fi
  done
  credential=$(uuid_new)
  exp=$(expire_date_minutes "$mins")
  xray::add_client "$protocol" "$username" "$credential"
  mkdir -p "$(dirname "$(xray::limit_file "$protocol" "$username")")"
  echo 1 > "$(xray::limit_file "$protocol" "$username")"
  echo 1 > "/etc/xray/limit/ip/xray/ws/$username"
  echo 1 > "/etc/xray/limit/ip/xray/grpc/$username"
  db::upsert_xray "$protocol" "$username" "$credential" "$exp" 1 active
  xray::write_logs "$protocol" "$username" "$credential" "$exp" 1
  xray_restart
  mkdir -p /usr/local/katsu-panel/scripts/generated /etc/cron.d
  cat > "/usr/local/katsu-panel/scripts/generated/trial-expire-xray-${protocol}-${username}.sh" <<SCRIPT
#!/usr/bin/env bash
source /usr/local/katsu-panel/lib/common.sh
source /usr/local/katsu-panel/lib/xray.sh
xray::delete "$protocol" "$username" >/dev/null 2>&1 || true
rm -f "/etc/cron.d/trial-expire-xray-${protocol}-${username}" "\$0"
SCRIPT
  chmod +x "/usr/local/katsu-panel/scripts/generated/trial-expire-xray-${protocol}-${username}.sh"
  run_at=$(date -u -d "+$mins minutes" '+%M %H %d %m *')
  echo "$run_at root /usr/local/katsu-panel/scripts/generated/trial-expire-xray-${protocol}-${username}.sh" > "/etc/cron.d/trial-expire-xray-${protocol}-${username}"
  printf '%s\t%s\n' "$username" "$credential"
}

xray::set_iplimit() {
  local protocol="$1" username="$2" limit="$3" row credential exp status
  row=$(db::get_xray "$protocol" "$username")
  [[ -n "$row" ]] || { echo "Xray user not found" >&2; return 1; }
  credential=$(awk -F'\t' '{print $3}' <<<"$row")
  exp=$(awk -F'\t' '{print $4}' <<<"$row")
  status=$(awk -F'\t' '{print $6}' <<<"$row")
  echo "$limit" > "$(xray::limit_file "$protocol" "$username")"
  echo "$limit" > "/etc/xray/limit/ip/xray/ws/$username"
  echo "$limit" > "/etc/xray/limit/ip/xray/grpc/$username"
  db::upsert_xray "$protocol" "$username" "$credential" "$exp" "$limit" "$status"
  xray::write_logs "$protocol" "$username" "$credential" "$exp" "$limit"
}

xray::suspend() {
  local protocol="$1" username="$2" reason="${3:-sharing}" row credential exp limit
  row=$(db::get_xray "$protocol" "$username")
  [[ -n "$row" ]] || return 0
  credential=$(awk -F'\t' '{print $3}' <<<"$row")
  exp=$(awk -F'\t' '{print $4}' <<<"$row")
  limit=$(awk -F'\t' '{print $5}' <<<"$row")
  xray::del_client "$protocol" "$username"
  echo "$reason" > "$KATSU_STATE/suspended/xray/${protocol}__${username}"
  db::upsert_xray "$protocol" "$username" "$credential" "$exp" "$limit" suspended
  xray_restart
}

xray::unsuspend() {
  local protocol="$1" username="$2" row credential exp limit
  row=$(db::get_xray "$protocol" "$username")
  [[ -n "$row" ]] || return 0
  credential=$(awk -F'\t' '{print $3}' <<<"$row")
  exp=$(awk -F'\t' '{print $4}' <<<"$row")
  limit=$(awk -F'\t' '{print $5}' <<<"$row")
  if xray::user_exists_in_config "$username"; then echo "Username already active in config" >&2; return 1; fi
  xray::add_client "$protocol" "$username" "$credential"
  rm -f "$KATSU_STATE/suspended/xray/${protocol}__${username}"
  db::upsert_xray "$protocol" "$username" "$credential" "$exp" "$limit" active
  xray::write_logs "$protocol" "$username" "$credential" "$exp" "$limit"
  xray_restart
}

xray::online_count() {
  local username="$1" out count
  if out=$(xray api statsonline --server=127.0.0.1:10085 -email "$username" 2>/dev/null); then
    count=$(jq -r '.stat.value // 0' <<<"$out" 2>/dev/null || echo 0)
    [[ "$count" =~ ^[0-9]+$ ]] && { echo "$count"; return 0; }
  fi
  local logfile="/var/log/xray/access.log"
  [[ -f "$logfile" ]] || { echo 0; return 0; }
  tail -n 4000 "$logfile" 2>/dev/null | grep -F "$username" | grep -Eo 'tcp:[0-9]{1,3}(\.[0-9]{1,3}){3}:[0-9]+|([0-9]{1,3}\.){3}[0-9]{1,3}:[0-9]+' | sed -E 's#^tcp:##; s#:[0-9]+$##' | sort -u | wc -l
}

xray::traffic_bytes() {
  local username="$1" direction="$2"
  xray api statsquery --server=127.0.0.1:10085 2>/dev/null | jq -r --arg u "$username" --arg d "$direction" '.stat[]? | select(.name|contains("user>>>"+$u+">>>traffic>>>"+$d)) | .value' | head -n1
}

xray::print_account() {
  local protocol="$1" username="$2" credential="$3" exp="$4"
  local domain city isp path grpc_service
  domain=$(read_domain)
  city=$(xray::geo_city)
  isp=$(xray::geo_isp)
  path=$(xray::ws_path "$protocol")
  grpc_service=$(xray::grpc_service "$protocol")
  case "$protocol" in
    vmess)
      cat <<TXT
┌─────────────────────────────────────────────────────────┐
                  PREMIUM VMESS ACCOUNT
└─────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────┐
│  User          : $username
│  ISP           : $isp
│  City          : $city
│  Domain        : $domain
│  Port TLS      : 443
│  Port NTLS     : 80
│  Port gRPC     : 443
│  UUID          : $credential
│  alterId       : 0
│  Security      : auto
│  Network       : ws
│  Path          : $path
│  Path Support  : http://bug$path
│  ServiceName   : $grpc_service
├─────────────────────────────────────────────────────────┤
│  Link Websocket TLS :
│  $(xray::vmess_ws_tls_link "$username" "$credential")
├─────────────────────────────────────────────────────────┤
│  Link Websocket NTLS :
│  $(xray::vmess_ws_ntls_link "$username" "$credential")
├─────────────────────────────────────────────────────────┤
│  Link gRPC :
│  $(xray::vmess_grpc_link "$username" "$credential")
├─────────────────────────────────────────────────────────┤
│  Format Openclash    : http://$domain:81/vmess-$username.txt
├─────────────────────────────────────────────────────────┤
│  Expired Akun       : $exp
└─────────────────────────────────────────────────────────┘
TXT
      ;;
    vless)
      cat <<TXT
┌─────────────────────────────────────────────────────────┐
                  PREMIUM VLESS ACCOUNT
└─────────────────────────────────────────────────────────┘
User        : $username
Domain      : $domain
UUID        : $credential
Path        : $path
ServiceName : $grpc_service
Link WS     : $(xray::vless_ws_link "$username" "$credential")
Link gRPC   : $(xray::vless_grpc_link "$username" "$credential")
Expired     : $exp
TXT
      ;;
    trojan)
      cat <<TXT
┌─────────────────────────────────────────────────────────┐
                 PREMIUM TROJAN ACCOUNT
└─────────────────────────────────────────────────────────┘
User        : $username
Domain      : $domain
Password    : $credential
Path        : $path
ServiceName : $grpc_service
Link WS     : $(xray::trojan_ws_link "$username" "$credential")
Link gRPC   : $(xray::trojan_grpc_link "$username" "$credential")
Expired     : $exp
TXT
      ;;
  esac
}
