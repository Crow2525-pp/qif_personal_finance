#!/usr/bin/env bash
set -e

if [[ -z "${VNC_PASSWORD:-}" ]]; then
  echo "Set VNC_PASSWORD before running this helper." >&2
  echo "Connect via localhost:5900, or use an SSH tunnel if running remotely." >&2
  exit 1
fi

docker run -it --rm \
  -p 127.0.0.1:5900:5900 \
  -e VNC_PASSWORD \
  -v coles-llm-shopper_coles_data:/app/data \
  coles-shopper bash -c 'apt-get install -y -q x11vnc 2>/dev/null; Xvfb :99 -screen 0 1280x1024x24 & sleep 2; x11vnc -storepasswd "$VNC_PASSWORD" /tmp/x11vnc.pass >/dev/null; x11vnc -display :99 -rfbauth /tmp/x11vnc.pass -listen 127.0.0.1 -rfbport 5900 -forever -quiet & sleep 2; DISPLAY=:99 PLAYWRIGHT_HEADED=1 coles-shopper auth --state /app/data/state/coles_state.json'
