#!/usr/bin/env bash
set -euo pipefail

source /usr/local/katsu-panel/lib/common.sh
source /usr/local/katsu-panel/lib/ui.sh
ensure_root

TMP_ROOT=""
cleanup() { [[ -n "$TMP_ROOT" && -d "$TMP_ROOT" ]] && rm -rf "$TMP_ROOT"; }
trap cleanup EXIT

fetch() {
  local url="$1" out="$2"
  mkdir -p "$(dirname "$out")"
  curl -fsSL --retry 3 --connect-timeout 20 "$url" -o "$out"
}

main() {
  local domain email repo_base root line
  domain=$(read_domain)
  email=$(read_email)
  repo_base=$(cfg_get KATSU_REPO_BASE '')
  [[ -n "$domain" ]] || { ui::err 'Domain belum tersimpan. Tidak bisa update otomatis.'; exit 1; }
  [[ -n "$repo_base" ]] || { ui::err 'Source update tidak ada di /etc/katsu-panel/panel.conf'; exit 1; }

  ui::clear
  ui::banner
  ui::title 'KATSU PANEL UPDATE'
  ui::kv 'Source' "$repo_base"
  ui::kv 'Domain' "$domain"
  ui::softline
  ui::info 'Mengunduh source terbaru...'

  TMP_ROOT=$(mktemp -d)
  root="$TMP_ROOT/project"
  mkdir -p "$root"
  fetch "$repo_base/manifest.txt" "$TMP_ROOT/manifest.txt"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    fetch "$repo_base/$line" "$root/$line"
  done < "$TMP_ROOT/manifest.txt"

  [[ -f "$root/scripts/setup.sh" ]] || { ui::err 'scripts/setup.sh tidak ditemukan di source update'; exit 1; }
  find "$root" -type f -name '*.sh' -exec chmod +x {} +

  export KATSU_DOMAIN="$domain"
  export KATSU_ACME_EMAIL="$email"
  export KATSU_REPO_BASE="$repo_base"
  export KATSU_UPDATE_MODE=1
  export KATSU_SKIP_REBOOT=1

  ui::info 'Menjalankan update autoscript...'
  exec bash "$root/scripts/setup.sh"
}

main "$@"
