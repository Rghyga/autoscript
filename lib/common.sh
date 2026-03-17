#!/usr/bin/env bash
set -euo pipefail

export KATSU_ROOT="/usr/local/katsu-panel"
export KATSU_ETC="/etc/katsu-panel"
export KATSU_DB="$KATSU_ETC/db"
export KATSU_STATE="$KATSU_ETC/state"
export KATSU_RUNTIME="$KATSU_ETC/runtime"
export KATSU_LOG="/var/log/katsu-panel"
export KATSU_CREATE_LOG="/var/log/create"
export KATSU_XRAY_CFG="/usr/local/etc/xray/config.json"
export KATSU_XRAY_JSON_DIR="/etc/xray/json"
export KATSU_WS_CFG="$KATSU_XRAY_JSON_DIR/ws.json"
export KATSU_GRPC_CFG="$KATSU_XRAY_JSON_DIR/grpc.json"
export KATSU_NGINX_SITE="/etc/nginx/sites-available/katsu-panel.conf"
export KATSU_DOMAIN_FILE="$KATSU_ETC/domain"
export KATSU_EMAIL_FILE="$KATSU_ETC/acme_email"
export KATSU_IFACE_FILE="$KATSU_ETC/interface"
export KATSU_CERT_DIR="/etc/ssl/katsu-panel"
export KATSU_WEBROOT="/var/www/katsu-panel"
export KATSU_XRAY_USERS="$KATSU_ETC/users/xray"
export KATSU_SSH_USERS="$KATSU_ETC/users/ssh"
export PATH="$PATH:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

ensure_root() {
  if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
    echo "Please run as root" >&2
    exit 1
  fi
}

init_dirs() {
  mkdir -p "$KATSU_DB" "$KATSU_STATE" "$KATSU_RUNTIME" "$KATSU_LOG" \
           "$KATSU_STATE/iplimits/ssh" \
           "$KATSU_STATE/iplimits/xray/vmess" "$KATSU_STATE/iplimits/xray/vless" "$KATSU_STATE/iplimits/xray/trojan" \
           "$KATSU_STATE/suspended/ssh" "$KATSU_STATE/suspended/xray" \
           "$KATSU_CERT_DIR" "$KATSU_WEBROOT/.well-known/acme-challenge" \
           "$KATSU_XRAY_USERS/vmess" "$KATSU_XRAY_USERS/vless" "$KATSU_XRAY_USERS/trojan" \
           "$KATSU_SSH_USERS" "$KATSU_CREATE_LOG/ssh" \
           "$KATSU_CREATE_LOG/xray/ws" "$KATSU_CREATE_LOG/xray/grpc" \
           /etc/xray/limit/ip/ssh /etc/xray/limit/ip/xray/ws /etc/xray/limit/ip/xray/grpc \
           /etc/xray/quota/ws /etc/xray/quota/grpc "$KATSU_XRAY_JSON_DIR"
  touch "$KATSU_DB/ssh.db" "$KATSU_DB/xray.db"
}

log() {
  local level=${1:-INFO}; shift || true
  mkdir -p "$KATSU_LOG"
  printf '[%s] [%s] %s\n' "$(date '+%F %T')" "$level" "$*" | tee -a "$KATSU_LOG/panel.log" >/dev/null
}

have() { command -v "$1" >/dev/null 2>&1; }
service_exists() { systemctl list-unit-files "$1" >/dev/null 2>&1; }

cfg_get() {
  local key="$1" default="${2:-}"
  [[ -f "$KATSU_ETC/panel.conf" ]] || { printf '%s' "$default"; return 0; }
  local val
  val=$(grep -E "^${key}=" "$KATSU_ETC/panel.conf" | tail -n1 | cut -d= -f2- || true)
  printf '%s' "${val:-$default}"
}

cfg_set() {
  local key="$1" value="$2"
  mkdir -p "$KATSU_ETC"
  touch "$KATSU_ETC/panel.conf"
  if grep -qE "^${key}=" "$KATSU_ETC/panel.conf"; then
    sed -i "s#^${key}=.*#${key}=${value}#" "$KATSU_ETC/panel.conf"
  else
    echo "${key}=${value}" >> "$KATSU_ETC/panel.conf"
  fi
}

today_epoch() { date +%s; }
expire_date_days() { date -u -d "+${1} day" +%F; }
expire_date_minutes() { date -u -d "+${1} minute" +%FT%TZ; }
random_string() { tr -dc 'a-z0-9' </dev/urandom | head -c "${1:-8}"; }
uuid_new() { cat /proc/sys/kernel/random/uuid; }
read_domain() { [[ -f "$KATSU_DOMAIN_FILE" ]] && cat "$KATSU_DOMAIN_FILE" || true; }
read_email() { [[ -f "$KATSU_EMAIL_FILE" ]] && cat "$KATSU_EMAIL_FILE" || true; }
valid_username() { [[ "$1" =~ ^[a-zA-Z0-9_-]{3,32}$ ]]; }

safe_restart() {
  local svc="$1"
  systemctl daemon-reload
  systemctl restart "$svc"
}

xray_restart() {
  if systemctl list-unit-files xray@.service >/dev/null 2>&1; then
    safe_restart xray@ws || true
    safe_restart xray@grpc || true
  else
    safe_restart xray
  fi
}
nginx_restart() { safe_restart nginx; }

katsu_iface() {
  if [[ -f "$KATSU_IFACE_FILE" ]]; then cat "$KATSU_IFACE_FILE"; return; fi
  ip route get 1.1.1.1 2>/dev/null | awk '/dev/ {for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}'
}

service_state() {
  local svc="$1"
  systemctl is-active "$svc" 2>/dev/null || echo inactive
}

public_ip() {
  local ip=""
  for url in \
    https://api.ipify.org \
    https://ipv4.icanhazip.com \
    https://ifconfig.me/ip \
    https://checkip.amazonaws.com
  do
    ip=$(curl -4fsSL --max-time 8 "$url" 2>/dev/null | tr -d '[:space:]' || true)
    [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && { printf '%s\n' "$ip"; return 0; }
  done
  ip -4 route get 1.1.1.1 2>/dev/null | awk '/src/ {for(i=1;i<=NF;i++) if($i=="src") {print $(i+1); exit}}'
}

resolve_domain_ipv4() {
  local domain="$1"
  if have dig; then
    dig +short A "$domain" @1.1.1.1 2>/dev/null | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' | head -n1
    return 0
  fi
  getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1}' | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' | head -n1
}

wait_domain_ready() {
  local domain="$1" tries="${2:-24}" sleep_sec="${3:-10}" i actual expected
  expected=$(public_ip)
  for ((i=1; i<=tries; i++)); do
    actual=$(resolve_domain_ipv4 "$domain")
    if [[ -n "$expected" && -n "$actual" && "$expected" == "$actual" ]]; then
      return 0
    fi
    log INFO "Waiting DNS propagation for $domain (attempt $i/$tries, resolved=${actual:-none}, expected=${expected:-unknown})"
    sleep "$sleep_sec"
  done
  return 1
}

port_open_local() {
  local port="$1"
  ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)${port}$"
}
