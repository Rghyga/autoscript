#!/usr/bin/env bash
set -euo pipefail
source /usr/local/katsu-panel/lib/common.sh
ensure_root
init_dirs

domain="${1:-$(read_domain)}"
mode="${2:-tls}"
[[ -n "$domain" ]] || { echo "Domain is empty" >&2; exit 1; }

mkdir -p "$KATSU_WEBROOT/.well-known/acme-challenge" /etc/nginx/conf.d /etc/nginx/sites-available /etc/nginx/sites-enabled
echo '<html><body>KATSU PANEL</body></html>' > "$KATSU_WEBROOT/index.html"

if [[ "$mode" == "challenge" ]]; then
  sed \
    -e "s#__DOMAIN__#${domain}#g" \
    -e "s#__WEBROOT__#${KATSU_WEBROOT//\//\\/}#g" \
    /usr/local/katsu-panel/templates/nginx-challenge.conf > "$KATSU_NGINX_SITE"
else
  fullchain="$KATSU_CERT_DIR/fullchain.cer"
  key="$KATSU_CERT_DIR/private.key"
  [[ -f "$fullchain" && -f "$key" ]] || { echo "Certificate not found" >&2; exit 1; }
  sed \
    -e "s#__DOMAIN__#${domain}#g" \
    -e "s#__FULLCHAIN__#${fullchain//\//\\/}#g" \
    -e "s#__KEY__#${key//\//\\/}#g" \
    /usr/local/katsu-panel/templates/nginx-katsu.conf > "$KATSU_NGINX_SITE"
fi

cp "$KATSU_NGINX_SITE" /etc/nginx/conf.d/katsu.conf
ln -sf "$KATSU_NGINX_SITE" /etc/nginx/sites-enabled/katsu-panel.conf
rm -f /etc/nginx/sites-enabled/default /etc/nginx/conf.d/default.conf
nginx -t
systemctl enable nginx
nginx_restart
