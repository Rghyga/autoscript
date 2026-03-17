#!/usr/bin/env bash
set -euo pipefail
source /usr/local/katsu-panel/lib/common.sh
ensure_root

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y \
  curl wget git gnupg ca-certificates lsb-release apt-transport-https software-properties-common \
  nginx vnstat fail2ban cron ufw jq unzip uuid-runtime openssl socat xz-utils dnsutils tar sed gawk \
  coreutils procps zip nano screen at rsync python3 python3-websockets

systemctl enable --now cron vnstat nginx fail2ban
