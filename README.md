# KATSU PANEL

Commercial-style autoscript for Debian 10/11/12 and Ubuntu 20.04/22.04/24.04.

## Included services
- openssh-server
- dropbear
- nginx
- xray-core
- fail2ban
- vnstat
- cron
- ufw
- acme.sh
- katsu-sshws websocket bridge

## Supported protocols
- SSH WS
- SSH SSL WS
- VMESS WS + gRPC
- VLESS WS + gRPC
- TROJAN WS + gRPC

## Project layout
- `install` bootstrap installer
- `update` update wrapper
- `menu/` interactive CLI menus
- `lib/` shared shell libraries
- `scripts/` installer and maintenance scripts
- `templates/` nginx/xray/login templates
- `systemd/` panel services
- `config/defaults.conf` repo/email bootstrap defaults

## Before upload
Edit `config/defaults.conf`:

```bash
KATSU_GITHUB_REPO="YOURUSER/your-repo"
KATSU_GITHUB_BRANCH="main"
KATSU_ZIP_URL=""
KATSU_ACME_EMAIL="admin@yourdomain.com"
```

Domain is prompted every install.

## Install command
```bash
sysctl -w net.ipv6.conf.all.disable_ipv6=1 && sysctl -w net.ipv6.conf.default.disable_ipv6=1 && apt update && apt-get update && apt-get update --fix-missing && apt install gnupg -y && apt-get install wget -y && apt-get install curl -y && apt-get install screen -y && wget -qO install https://raw.githubusercontent.com/Rghyga/autoscript/master/install && chmod +x install && ./install
```
## Update on VPS
```bash
update
```

## Notes
Jika terjadi diskonek silahkan ketik ☞ screen -d -r install untuk kembali ke sesi install

- TLS certificate issuance requires the domain A record to already point to the VPS public IPv4.
- Installer reboots the VPS 10 seconds after a fresh install completes.
- Backup/restore is included, but restore is still safest when used with backups produced by the same KATSU PANEL build.
