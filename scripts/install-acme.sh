#!/usr/bin/env bash
set -euo pipefail
source /usr/local/katsu-panel/lib/common.sh
ensure_root
init_dirs

email="${1:-$(read_email)}"
[[ -n "$email" ]] || { echo "ACME email is required" >&2; exit 1; }

if [[ ! -x /root/.acme.sh/acme.sh ]]; then
  curl -fsSL https://get.acme.sh | sh -s email="$email"
fi
/root/.acme.sh/acme.sh --set-default-ca --server letsencrypt
/root/.acme.sh/acme.sh --upgrade --auto-upgrade >/dev/null 2>&1 || true
