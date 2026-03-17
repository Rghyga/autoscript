#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
trap 'echo "[ERR] setup failed at line $LINENO" >&2' ERR

mkdir -p /usr/local
rm -rf /usr/local/katsu-panel
cp -a . /usr/local/katsu-panel
find /usr/local/katsu-panel -type f -name '*.sh' -exec chmod +x {} +
chmod +x /usr/local/katsu-panel/install /usr/local/katsu-panel/update /usr/local/katsu-panel/setup.sh || true

source /usr/local/katsu-panel/lib/common.sh
source /usr/local/katsu-panel/lib/ui.sh
ensure_root
init_dirs

ui::clear
ui::banner
ui::title 'KATSU PANEL SETUP WIZARD'
update_mode=${KATSU_UPDATE_MODE:-0}

os_id=$(source /etc/os-release && echo "$ID")
os_ver=$(source /etc/os-release && echo "$VERSION_ID")
case "$os_id:$os_ver" in
  debian:10|debian:11|debian:12|ubuntu:20.04|ubuntu:22.04|ubuntu:24.04) ;;
  *) ui::err "Unsupported OS: $os_id $os_ver"; exit 1 ;;
esac

iface=$(ip route get 1.1.1.1 | awk '/dev/ {for(i=1;i<=NF;i++) if($i=="dev") {print $(i+1); exit}}')
echo "$iface" > "$KATSU_IFACE_FILE"

[[ -f /usr/local/katsu-panel/config/defaults.conf ]] && source /usr/local/katsu-panel/config/defaults.conf || true
domain="${KATSU_DOMAIN:-${DOMAIN:-}}"
email="${KATSU_ACME_EMAIL:-${ACME_EMAIL:-}}"
repo_base="${KATSU_REPO_BASE:-${REPO_BASE:-}}"
repo_name="${KATSU_GITHUB_REPO:-}"
repo_branch="${KATSU_GITHUB_BRANCH:-master}"
ui::clear
ui::banner
ui::title 'DOMAIN CONFIGURATION'
[[ -n "$domain" ]] || ui::prompt 'Input domain: ' domain
[[ -n "$domain" ]] || { ui::err 'Domain is required'; exit 1; }
[[ -n "$email" ]] || email="admin@${domain}"

echo "$domain" > "$KATSU_DOMAIN_FILE"
echo "$email" > "$KATSU_EMAIL_FILE"
[[ -n "$repo_name" ]] && cfg_set KATSU_GITHUB_REPO "$repo_name"
[[ -n "$repo_branch" ]] && cfg_set KATSU_GITHUB_BRANCH "$repo_branch"
[[ -n "$repo_base" ]] && cfg_set KATSU_REPO_BASE "$repo_base"
cfg_set KATSU_DOMAIN "$domain"
cfg_set KATSU_ACME_EMAIL "$email"

server_ip=$(public_ip)
resolved_ip=$(resolve_domain_ipv4 "$domain" || echo unresolved)
ui::subtitle 'Installation Summary'
ui::kv 'Mode' "$([[ "$update_mode" == "1" ]] && echo Update || echo Fresh Install)"
ui::kv 'Project' 'KATSU PANEL'
ui::kv 'OS' "$os_id $os_ver"
ui::kv 'Interface' "$iface"
ui::kv 'Public IP' "${server_ip:-unknown}"
ui::kv 'Domain' "$domain"
ui::kv 'Resolved IPv4' "$resolved_ip"
ui::kv 'ACME Email' "$email"
ui::softline

if ! wait_domain_ready "$domain" 12 10; then
  ui::warn 'Domain belum resolve ke VPS ini. Installer dihentikan agar sertifikat tidak gagal.'
  exit 1
fi

step=1; total=10
ui::step "$step" "$total" 'Installing required packages'; bash /usr/local/katsu-panel/scripts/install-packages.sh; step=$((step+1))
ui::step "$step" "$total" 'Installing SSH stack'; bash /usr/local/katsu-panel/scripts/install-ssh-stack.sh; step=$((step+1))
ui::step "$step" "$total" 'Installing Xray core'; bash /usr/local/katsu-panel/scripts/install-xray.sh; step=$((step+1))
ui::step "$step" "$total" 'Preparing nginx ACME challenge'; bash /usr/local/katsu-panel/scripts/configure-nginx.sh "$domain" challenge; step=$((step+1))
ui::step "$step" "$total" 'Installing acme.sh'; bash /usr/local/katsu-panel/scripts/install-acme.sh "$email"; step=$((step+1))
ui::step "$step" "$total" 'Issuing TLS certificate'; bash /usr/local/katsu-panel/scripts/issue-cert.sh "$domain" "$email"; step=$((step+1))
ui::step "$step" "$total" 'Applying nginx production config'; bash /usr/local/katsu-panel/scripts/configure-nginx.sh "$domain" tls; step=$((step+1))
ui::step "$step" "$total" 'Configuring firewall'; bash /usr/local/katsu-panel/scripts/configure-ufw.sh; step=$((step+1))
ui::step "$step" "$total" 'Configuring fail2ban'; systemctl restart fail2ban || true; step=$((step+1))
ui::step "$step" "$total" 'Installing internal services'
cp /usr/local/katsu-panel/systemd/katsu-* /etc/systemd/system/
chmod +x /usr/local/katsu-panel/scripts/iplimit-monitor.sh /usr/local/katsu-panel/scripts/expire-check.sh /usr/local/katsu-panel/scripts/self-check.sh
ln -sf /usr/local/katsu-panel/menu/main.sh /usr/local/bin/menu
ln -sf /usr/local/katsu-panel/menu/main.sh /usr/local/bin/katsu-menu
ln -sf /usr/local/katsu-panel/update /usr/local/bin/update
ln -sf /usr/local/katsu-panel/scripts/self-check.sh /usr/local/bin/katsu-selfcheck
cp /usr/local/katsu-panel/templates/katsu-welcome.sh /etc/profile.d/katsu-welcome.sh
chmod +x /etc/profile.d/katsu-welcome.sh
mkdir -p "$KATSU_WEBROOT/files"
systemctl daemon-reload
systemctl enable --now katsu-iplimit
systemctl enable --now katsu-expire.timer
systemctl enable katsu-selfcheck || true
systemctl start katsu-selfcheck || true

ui::softline
ui::info 'Running final self-check...'
/usr/local/katsu-panel/scripts/self-check.sh --strict || true
ui::ok 'KATSU PANEL installed successfully'
ui::kv 'Command' 'menu'
ui::kv 'Update' 'update'
ui::kv 'Self Check' 'katsu-selfcheck'

if [[ "$update_mode" == "0" && "${KATSU_SKIP_REBOOT:-0}" != "1" ]]; then
  echo
  ui::warn 'VPS will reboot automatically in 10 seconds.'
  sleep 10
  reboot
fi
