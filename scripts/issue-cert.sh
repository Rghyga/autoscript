#!/usr/bin/env bash
set -euo pipefail
source /usr/local/katsu-panel/lib/common.sh
ensure_root
init_dirs

domain="${1:-$(read_domain)}"
email="${2:-$(read_email)}"
[[ -n "$domain" && -n "$email" ]] || { echo "Usage: $0 <domain> <email>" >&2; exit 1; }

echo "$domain" > "$KATSU_DOMAIN_FILE"
echo "$email" > "$KATSU_EMAIL_FILE"

server_ip=$(public_ip)
resolved_ip=$(resolve_domain_ipv4 "$domain" || true)
if ! wait_domain_ready "$domain" 18 10; then
  echo "Domain $domain belum mengarah ke VPS ini. Resolved=${resolved_ip:-none}, VPS=${server_ip:-unknown}" >&2
  exit 1
fi

bash /usr/local/katsu-panel/scripts/configure-nginx.sh "$domain" challenge
/root/.acme.sh/acme.sh --register-account -m "$email" --server letsencrypt >/dev/null 2>&1 || true

issue_ok=0
if /root/.acme.sh/acme.sh --issue -d "$domain" -w "$KATSU_WEBROOT" --keylength ec-256 --server letsencrypt; then
  issue_ok=1
else
  log WARN "ACME webroot issue failed for $domain, trying standalone fallback"
  systemctl stop nginx || true
  if /root/.acme.sh/acme.sh --issue -d "$domain" --standalone --keylength ec-256 --server letsencrypt; then
    issue_ok=1
  fi
fi
(( issue_ok == 1 )) || { echo "Failed issuing certificate for $domain" >&2; systemctl start nginx || true; exit 1; }

mkdir -p "$KATSU_CERT_DIR"
/root/.acme.sh/acme.sh --install-cert -d "$domain" --ecc \
  --fullchain-file "$KATSU_CERT_DIR/fullchain.cer" \
  --key-file "$KATSU_CERT_DIR/private.key" \
  --reloadcmd "systemctl restart nginx && systemctl restart xray"
chmod 600 "$KATSU_CERT_DIR/private.key"
chmod 644 "$KATSU_CERT_DIR/fullchain.cer"
systemctl start nginx || true
