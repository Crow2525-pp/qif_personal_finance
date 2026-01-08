# Deployment Guide - Git-Based Workflow

This guide explains how to work locally and deploy to your remote server via Portainer.

## Overview

**Local Development** → **Push to GitHub** → **Remote Server Pulls & Deploys**

## Setup Instructions

### 1. One-Time Server Setup

#### Option A: Manual Deployment (Recommended to Start)
Simply SSH into your server and run:
```bash
cd /docker/appdata/qif_personal_finance
./scripts/portainer-deploy.sh
```

#### Option B: Automated Polling (Cron-Based)
Set up automatic checks every 15 minutes:

```bash
# Edit crontab
crontab -e

# Add this line to check for updates every 15 minutes
*/15 * * * * /docker/appdata/qif_personal_finance/scripts/portainer-deploy.sh >> /docker/appdata/qif_personal_finance/scripts/deploy.log 2>&1
```

#### Option C: Webhook-Based Deployment (Most Advanced)

**Using Portainer Webhooks:**
1. Access Portainer UI at `https://your-server:9443`
2. Navigate to your stack
3. Enable "Webhook" in stack settings
4. Copy the webhook URL
5. Add webhook to GitHub:
   - Go to your repo: `https://github.com/Crow2525-pp/qif_personal_finance/settings/hooks`
   - Add webhook with Portainer URL
   - Content type: `application/json`
   - Events: Just push events

**Alternative: Using webhook relay service:**
```bash
# Install webhook tool
sudo apt-get install webhook

# Configure webhook listener
cat > /etc/webhook.conf <<'EOF'
[
  {
    "id": "qif-deploy",
    "execute-command": "/docker/appdata/qif_personal_finance/scripts/portainer-webhook.sh",
    "command-working-directory": "/docker/appdata/qif_personal_finance",
    "response-message": "Deployment triggered"
  }
]
EOF

# Start webhook service
webhook -hooks /etc/webhook.conf -verbose -port 9000
```

### 2. Local Development Workflow

On your local machine:

```bash
# Clone the repository (one time)
git clone git@github.com:Crow2525-pp/qif_personal_finance.git
cd qif_personal_finance

# Make your changes
# ... edit files ...

# Commit and push
git add .
git commit -m "Your change description"
git push origin main
```

### 3. Deploy to Remote Server

Choose your deployment method:

**Manual (Immediate):**
```bash
# SSH into server one time
ssh user@your-server
cd /docker/appdata/qif_personal_finance
./scripts/portainer-deploy.sh
```

**Automatic (if cron or webhook configured):**
- Cron: Wait up to 15 minutes
- Webhook: Triggers immediately on push

## What the Deploy Script Does

1. Fetches latest changes from GitHub
2. Checks if updates are available
3. Pulls new code if changes detected
4. Rebuilds Docker images with `--no-cache`
5. Restarts services with zero downtime goal
6. Cleans up old Docker images

## Deployment Logs

View deployment logs:
```bash
tail -f /docker/appdata/qif_personal_finance/scripts/deploy.log
```

## Manual Deployment Commands

If you need more control:

```bash
# Navigate to repo
cd /docker/appdata/qif_personal_finance

# Pull latest changes
git pull origin main

# Rebuild images
docker-compose build --no-cache

# Restart services
docker-compose down && docker-compose up -d

# View logs
docker-compose logs -f
```

## Testing Changes

Before pushing to production:

1. Test locally using Docker Compose if possible
2. Push to a feature branch first
3. Test deployment on server from feature branch:
   ```bash
   BRANCH=feature-branch ./scripts/portainer-deploy.sh
   ```
4. Merge to main when ready

## Troubleshooting

### Deployment Failed
```bash
# Check logs
tail -n 50 /docker/appdata/qif_personal_finance/scripts/deploy.log

# Check Docker status
docker-compose ps

# Manually restart
cd /docker/appdata/qif_personal_finance
docker-compose restart
```

### Git Authentication Issues
The server needs SSH key access to GitHub:
```bash
# Generate SSH key on server (if needed)
ssh-keygen -t ed25519 -C "your-server@example.com"

# Add public key to GitHub
cat ~/.ssh/id_ed25519.pub
# Copy this to GitHub Settings → SSH Keys
```

### Permission Issues
```bash
# Fix script permissions
chmod +x /docker/appdata/qif_personal_finance/scripts/*.sh
```

## Recommended Workflow

For most use cases, I recommend:

1. **Daily development**: Work locally, push to GitHub frequently
2. **Deploy when ready**: SSH in once and run `./scripts/portainer-deploy.sh`
3. **No cron needed**: Manual control prevents unexpected changes

This gives you full control without dealing with SSH instability during development.

## Notes

- The deployment script uses `--no-cache` to ensure clean builds
- Stashes local changes automatically (shouldn't happen in production)
- Pulls from `main` branch by default (override with `BRANCH` env var)
- Cleans up old Docker images to save space
