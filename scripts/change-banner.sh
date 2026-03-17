#!/usr/bin/env bash
set -euo pipefail
ensure_root() { [[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'run as root' >&2; exit 1; }; }
ensure_root
mkdir -p /usr/local/katsu-panel/config
cp -f /etc/issue.net /usr/local/katsu-panel/config/banner.custom 2>/dev/null || cp -f /usr/local/katsu-panel/config/banner.default /usr/local/katsu-panel/config/banner.custom
editor="${EDITOR:-nano}"
$editor /usr/local/katsu-panel/config/banner.custom
bash /usr/local/katsu-panel/scripts/apply-banner.sh /usr/local/katsu-panel/config/banner.custom
