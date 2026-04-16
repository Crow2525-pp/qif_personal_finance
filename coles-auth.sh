#!/usr/bin/env bash
set -e
docker run -it --rm -p 5900:5900 -v coles-llm-shopper_coles_data:/app/data coles-shopper bash -c 'apt-get install -y -q x11vnc 2>/dev/null; Xvfb :99 -screen 0 1280x1024x24 & sleep 2; x11vnc -display :99 -nopw -listen 0.0.0.0 -rfbport 5900 -forever -quiet & sleep 2; DISPLAY=:99 PLAYWRIGHT_HEADED=1 coles-shopper auth --state /app/data/state/coles_state.json'
