#!/usr/bin/env bash
set -euo pipefail
source /usr/local/katsu-panel/lib/common.sh
ensure_root
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 81/tcp
ufw allow 109/tcp
ufw allow 443/tcp
ufw --force enable
