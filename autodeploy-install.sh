#!/usr/bin/env bash
# Run ONCE on the server to make it watch GitHub and deploy itself.
#   cd ~/team2-src && chmod +x autodeploy-install.sh && ./autodeploy-install.sh
set -euo pipefail

sudo tee /etc/systemd/system/team2-deploy.service >/dev/null <<UNIT
[Unit]
Description=Deploy Team2 when GitHub has new commits
After=network-online.target

[Service]
Type=oneshot
User=$USER
WorkingDirectory=$HOME/team2-src
ExecStart=/bin/bash -c 'git fetch --quiet origin main && [ "\$(git rev-parse HEAD)" != "\$(git rev-parse origin/main)" ] && exec $HOME/team2-src/deploy.sh || echo "already current"'
UNIT

sudo tee /etc/systemd/system/team2-deploy.timer >/dev/null <<'UNIT'
[Unit]
Description=Check GitHub for Team2 updates every 2 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=2min
Unit=team2-deploy.service

[Install]
WantedBy=timers.target
UNIT

# deploy.sh needs sudo without a prompt, for the unattended run only
echo "$USER ALL=(root) NOPASSWD: /usr/bin/cp, /usr/bin/sed, /usr/bin/mkdir, /usr/bin/chown, /usr/bin/systemctl reload caddy" \
  | sudo tee /etc/sudoers.d/team2-deploy >/dev/null
sudo chmod 440 /etc/sudoers.d/team2-deploy

sudo systemctl daemon-reload
sudo systemctl enable --now team2-deploy.timer
systemctl list-timers team2-deploy.timer --no-pager | head -3
echo "auto-deploy is on — pushes to GitHub go live within 2 minutes"
