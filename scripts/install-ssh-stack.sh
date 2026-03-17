#!/usr/bin/env bash
set -euo pipefail
source /usr/local/katsu-panel/lib/common.sh
ensure_root

apt-get update -y
apt-get install -y openssh-server dropbear python3 python3-pip
python3 -m pip install --break-system-packages --quiet websockets >/dev/null 2>&1 || apt-get install -y python3-websockets || true
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/katsu-panel.conf <<CFG
PasswordAuthentication yes
PermitRootLogin prohibit-password
AllowTcpForwarding yes
X11Forwarding no
UseDNS no
ClientAliveInterval 120
ClientAliveCountMax 2
Banner /etc/issue.net
CFG

if [[ -f /etc/default/dropbear ]]; then
  sed -i 's/^NO_START=.*/NO_START=0/' /etc/default/dropbear || true
  sed -i 's/^DROPBEAR_PORT=.*/DROPBEAR_PORT=109/' /etc/default/dropbear || true
  if grep -q '^DROPBEAR_EXTRA_ARGS=' /etc/default/dropbear; then
    sed -i 's#^DROPBEAR_EXTRA_ARGS=.*#DROPBEAR_EXTRA_ARGS="-p 109 -w -g"#' /etc/default/dropbear
  else
    echo 'DROPBEAR_EXTRA_ARGS="-p 109 -w -g"' >> /etc/default/dropbear
  fi
fi

cat > /usr/local/katsu-panel/scripts/ssh-ws.py <<PY
#!/usr/bin/env python3
import asyncio
import websockets
TARGET_HOST='127.0.0.1'
TARGET_PORT=22
async def ws_handler(websocket):
    reader, writer = await asyncio.open_connection(TARGET_HOST, TARGET_PORT)
    async def ws_to_tcp():
        try:
            async for message in websocket:
                if isinstance(message, str):
                    message = message.encode()
                writer.write(message)
                await writer.drain()
        except Exception:
            pass
        finally:
            try:
                writer.close()
                await writer.wait_closed()
            except Exception:
                pass
    async def tcp_to_ws():
        try:
            while True:
                data = await reader.read(4096)
                if not data:
                    break
                await websocket.send(data)
        except Exception:
            pass
        finally:
            try:
                await websocket.close()
            except Exception:
                pass
    await asyncio.gather(ws_to_tcp(), tcp_to_ws())
async def main():
    async with websockets.serve(ws_handler, '127.0.0.1', 2082, max_size=None, ping_interval=None):
        await asyncio.Future()
asyncio.run(main())
PY
chmod +x /usr/local/katsu-panel/scripts/ssh-ws.py
cat > /etc/systemd/system/katsu-sshws.service <<SERVICE
[Unit]
Description=KATSU SSH WebSocket bridge
After=network.target ssh.service sshd.service

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/katsu-panel/scripts/ssh-ws.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
SERVICE

bash /usr/local/katsu-panel/scripts/apply-banner.sh
systemctl daemon-reload
systemctl enable --now ssh || systemctl enable --now sshd || true
systemctl enable --now dropbear || true
systemctl enable --now katsu-sshws
