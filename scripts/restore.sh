#!/bin/bash
set -euo pipefail

# Usage: ./scripts/restore.sh <resource-group> <redis-name>
# Restores the app to a healthy state after fault injection

if [ $# -lt 2 ]; then
  echo "Usage: $0 <resource-group> <redis-name>"
  exit 1
fi

RG="$1"
REDIS_NAME="$2"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Restoring healthy state ==="

# Get correct Redis credentials
echo "Fetching Redis access keys..."
REDIS_HOST="${REDIS_NAME}.redis.cache.windows.net"
REDIS_KEY=$(az redis list-keys --resource-group "$RG" --name "$REDIS_NAME" --query primaryKey -o tsv)

# Restore the Redis secret with correct values
echo "Updating Redis secret..."
kubectl create secret generic redis-secret \
  --namespace aks-journal-app \
  --from-literal=REDIS_HOST="$REDIS_HOST" \
  --from-literal=REDIS_PORT="6380" \
  --from-literal=REDIS_PASSWORD="$REDIS_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

# Restore the healthy deployment
echo "Applying healthy deployment..."
kubectl apply -f "$REPO_DIR/k8s/deployment.yaml"

# Restart pods to pick up new secret
echo "Restarting pods..."
kubectl rollout restart deployment/aks-journal -n aks-journal-app

echo "Waiting for rollout..."
kubectl rollout status deployment/aks-journal -n aks-journal-app --timeout=120s

echo "=== Restore complete ==="
kubectl get pods -n aks-journal-app
