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
NAMESPACE="aks-journal-app"

get_healthy_image() {
  kubectl get configmap sre-demo-state -n "$NAMESPACE" -o jsonpath='{.data.HEALTHY_IMAGE}' 2>/dev/null || true
}

HEALTHY_IMAGE="$(get_healthy_image)"
if [ -z "$HEALTHY_IMAGE" ]; then
  echo "Warning: No stored healthy image found in sre-demo-state. Falling back to the currently configured image."
  HEALTHY_IMAGE="$(kubectl get deployment aks-journal -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}')"
fi

if [ -z "$HEALTHY_IMAGE" ]; then
  echo "Error: Unable to determine a healthy image for restore."
  exit 1
fi

echo "=== Restoring healthy state ==="

# Get correct Redis credentials
echo "Fetching Redis access keys..."
REDIS_HOST="${REDIS_NAME}.redis.cache.windows.net"
REDIS_KEY=$(az redis list-keys --resource-group "$RG" --name "$REDIS_NAME" --query primaryKey -o tsv)

# Restore the Redis secret with correct values
echo "Updating Redis secret..."
kubectl create secret generic redis-secret \
  --namespace "$NAMESPACE" \
  --from-literal=REDIS_HOST="$REDIS_HOST" \
  --from-literal=REDIS_PORT="6380" \
  --from-literal=REDIS_PASSWORD="$REDIS_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

# Remove scenario-specific objects that healthy manifests won't delete
echo "Cleaning up scenario-specific resources..."
kubectl delete deployment resource-hog -n "$NAMESPACE" --ignore-not-found
kubectl delete networkpolicy deny-all-egress -n "$NAMESPACE" --ignore-not-found

# Restore healthy config and services
echo "Reapplying healthy manifests..."
kubectl apply -f "$REPO_DIR/k8s/configmap.yaml"
kubectl apply -f "$REPO_DIR/k8s/service.yaml"
kubectl apply -f "$REPO_DIR/k8s/mongodb.yaml"
sed "s|\${AZURE_CONTAINER_REGISTRY}/aks-journal:\${IMAGE_TAG}|${HEALTHY_IMAGE}|g" \
  "$REPO_DIR/k8s/deployment.yaml" | kubectl apply -f -

# Restore order-processor using the same image base as the journal app
OP_HEALTHY_IMAGE="${HEALTHY_IMAGE/\/aks-journal:/\/order-processor:}"
if kubectl get deployment order-processor -n "$NAMESPACE" &>/dev/null; then
  sed "s|\${AZURE_CONTAINER_REGISTRY}/order-processor:\${IMAGE_TAG}|${OP_HEALTHY_IMAGE}|g" \
    "$REPO_DIR/k8s/order-processor.yaml" | kubectl apply -f - >/dev/null
fi

# Restart pods to pick up restored config
echo "Restarting pods..."
kubectl rollout restart deployment/aks-journal -n "$NAMESPACE"
if kubectl get deployment order-processor -n "$NAMESPACE" &>/dev/null; then
  kubectl rollout restart deployment/order-processor -n "$NAMESPACE"
fi

echo "Waiting for rollout..."
kubectl rollout status deployment/aks-journal -n "$NAMESPACE" --timeout=180s
if kubectl get deployment order-processor -n "$NAMESPACE" &>/dev/null; then
  kubectl rollout status deployment/order-processor -n "$NAMESPACE" --timeout=120s
fi

echo "=== Restore complete ==="
kubectl get pods -n "$NAMESPACE"
