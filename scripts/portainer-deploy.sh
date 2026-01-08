#!/bin/bash
# Portainer Stack Deployment Script
# This script pulls the latest code from git and rebuilds the stack

set -e

echo "=== Portainer Stack Auto-Deploy ==="
echo "Starting deployment at $(date)"

# Configuration
REPO_DIR="/docker/appdata/qif_personal_finance"
BRANCH="${BRANCH:-main}"

# Navigate to repo directory
cd "$REPO_DIR"

# Fetch latest changes
echo "Fetching latest changes from origin..."
git fetch origin

# Check if there are updates
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/$BRANCH)

if [ "$LOCAL" = "$REMOTE" ]; then
    echo "No updates available. Current commit: $LOCAL"
    exit 0
fi

echo "Updates found. Pulling changes..."
echo "Current: $LOCAL"
echo "Remote:  $REMOTE"

# Stash any local changes (shouldn't be any in production)
if ! git diff-index --quiet HEAD --; then
    echo "Warning: Local changes detected. Stashing..."
    git stash
fi

# Pull latest changes
git pull origin "$BRANCH"

# Rebuild and restart services
echo "Rebuilding Docker images..."
docker-compose build --no-cache

echo "Restarting services..."
docker-compose down
docker-compose up -d

echo "Deployment completed successfully at $(date)"
echo "New commit: $(git rev-parse HEAD)"

# Clean up old images
echo "Cleaning up old Docker images..."
docker image prune -f
