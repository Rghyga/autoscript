#!/usr/bin/env bash
set -euo pipefail

C0='\033[0m'; W='\033[1;37m'; R='\033[1;31m'; G='\033[1;32m'; Y='\033[1;33m'; B='\033[1;34m'; M='\033[1;35m'; C='\033[1;36m'; D='\033[0;90m'

ui::clear() { clear 2>/dev/null || true; }
ui::line() { printf '%b%s%b\n' "$C" '┌─────────────────────────────────────────────────────────┐' "$C0"; }
ui::line2() { printf '%b%s%b\n' "$C" '├─────────────────────────────────────────────────────────┤' "$C0"; }
ui::endline() { printf '%b%s%b\n' "$C" '└─────────────────────────────────────────────────────────┘' "$C0"; }
ui::softline() { printf '%b%s%b\n' "$D" '---------------------------------------------------------' "$C0"; }
ui::title() {
  printf '%b%s%b\n' "$C" '┌─────────────────────────────────────────────────────────┐' "$C0"
  printf '%b %55s %b\n' "$W" "$1" "$C0"
  printf '%b%s%b\n' "$C" '└─────────────────────────────────────────────────────────┘' "$C0"
}
ui::red_title() {
  printf '%b%s%b\n' "$C" '┌─────────────────────────────────────────────────────────┐' "$C0"
  printf '%b│%23s%b%-9s%b%23s%b│\n' "$C" '' "$R" "$1" "$C" '' "$C0"
  printf '%b%s%b\n' "$C" '└─────────────────────────────────────────────────────────┘' "$C0"
}
ui::subtitle() { printf '%b%s%b\n' "$M" "$1" "$C0"; ui::softline; }
ui::ok() { printf '%b[OK]%b %s\n' "$G" "$C0" "$*"; }
ui::warn() { printf '%b[WARN]%b %s\n' "$Y" "$C0" "$*"; }
ui::err() { printf '%b[ERR]%b %s\n' "$R" "$C0" "$*"; }
ui::info() { printf '%b[INFO]%b %s\n' "$C" "$C0" "$*"; }
ui::kv() { printf ' %-20s : %s\n' "$1" "$2"; }
ui::pause() { read -r -p 'Press Enter to return to menu ' _; }
ui::menu_item() { printf ' [%b%s%b] %s\n' "$Y" "$1" "$C0" "$2"; }
ui::status() {
  local label="$1" svc="$2" st icon
  st=$(systemctl is-active "$svc" 2>/dev/null || echo inactive)
  if [[ "$st" == active ]]; then icon="${G}Running${C0}"; else icon="${R}${st^}${C0}"; fi
  printf ' • %-16s : %b\n' "$label" "$icon"
}
ui::badge() { printf '%b[%s]%b' "$1" "$2" "$C0"; }
ui::banner() {
  printf '%b%s%b\n' "$C" '────────────────────────────────────────────────────────────' "$C0"
  printf '%b %s%b\n' "$W" 'KATSU PANEL' "$C0"
  printf '%b%s%b\n' "$C" '────────────────────────────────────────────────────────────' "$C0"
}
ui::prompt() { read -r -p "$1" "$2"; }
ui::step() { printf '%b[%s/%s]%b %s\n' "$C" "$1" "$2" "$C0" "$3"; }
