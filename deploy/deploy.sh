#!/usr/bin/env bash
# Upload the current game + server to the Droplet and (re)start it.
#   deploy/deploy.sh <droplet-ip>
# Re-export the web build from Godot first (build/web). Player data on the server is kept
# (it lives in a Docker volume), and so is the server's .env file.
set -euo pipefail
IP="${1:?usage: deploy/deploy.sh <droplet-ip>}"
KEY="${KEY:-$HOME/.ssh/rocketrace_ed25519}"
SSH=(ssh -i "$KEY" -o StrictHostKeyChecking=accept-new "root@$IP")
cd "$(dirname "$0")/.."

echo "Packing..."
tar --exclude=server/node_modules --exclude=server/data -czf /tmp/rocket-race.tgz \
  Dockerfile .dockerignore docker-compose.yml catalog.json deploy server build/web

echo "Uploading to $IP..."
scp -i "$KEY" -o StrictHostKeyChecking=accept-new /tmp/rocket-race.tgz "root@$IP:/opt/rocket-race/"
"${SSH[@]}" "cd /opt/rocket-race && tar -xzf rocket-race.tgz && rm rocket-race.tgz && \
  (grep -q '^SITE_ADDRESS=' .env 2>/dev/null || echo SITE_ADDRESS=\$(echo $IP | tr . -).sslip.io >> .env) && \
  docker compose up -d --build && docker image prune -f >/dev/null && docker compose ps"
echo "Done: https://$(echo "$IP" | tr . -).sslip.io (or your domain, if set in .env)"
