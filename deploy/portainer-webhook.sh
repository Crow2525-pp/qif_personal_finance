#!/bin/bash
# Webhook handler script for Portainer
# Can be triggered via Portainer webhook or external webhook service

# Log to file
LOG_FILE="/docker/appdata/qif_personal_finance/deploy/deploy.log"
exec >> "$LOG_FILE" 2>&1

echo "=== Webhook Triggered at $(date) ==="

# Run the deployment script
/docker/appdata/qif_personal_finance/deploy/portainer-deploy.sh

echo "=== Webhook Completed at $(date) ==="
