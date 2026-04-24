#!/bin/bash
set -euo pipefail

# Usage: ./scripts/deploy-app.sh <resource-group> <acr-name> <aks-cluster-name> [image-tag]
# Builds both container images, pushes to ACR, and deploys all K8s manifests

if [ $# -lt 3 ]; then
  echo "Usage: $0 <resource-group> <acr-name> <aks-cluster-name> [image-tag]"
  exit 1
fi

RG="$1"
ACR_NAME="$2"
AKS_NAME="$3"
IMAGE_TAG="${4:-latest}"
ACR_LOGIN_SERVER="${ACR_NAME}.azurecr.io"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Logging in to ACR ==="
az acr login --name "$ACR_NAME"

echo "=== Building journal app image ==="
docker build -t "${ACR_LOGIN_SERVER}/aks-journal:${IMAGE_TAG}" "$REPO_DIR/app"

echo "=== Building order-processor image ==="
docker build -t "${ACR_LOGIN_SERVER}/order-processor:${IMAGE_TAG}" "$REPO_DIR/app-order-processor"

echo "=== Pushing images to ACR ==="
docker push "${ACR_LOGIN_SERVER}/aks-journal:${IMAGE_TAG}"
docker push "${ACR_LOGIN_SERVER}/order-processor:${IMAGE_TAG}"

echo "=== Getting AKS credentials ==="
az aks get-credentials --resource-group "$RG" --name "$AKS_NAME" --overwrite-existing

echo "=== Deploying K8s manifests ==="
kubectl apply -f "$REPO_DIR/k8s/namespace.yaml"
kubectl apply -f "$REPO_DIR/k8s/serviceaccount.yaml"
kubectl apply -f "$REPO_DIR/k8s/configmap.yaml"

# Get Redis details from Terraform outputs
REDIS_HOST=$(cd "$REPO_DIR/terraform" && terraform output -raw redis_hostname)
REDIS_PORT=$(cd "$REPO_DIR/terraform" && terraform output -raw redis_port)
REDIS_KEY=$(cd "$REPO_DIR/terraform" && terraform output -raw redis_primary_key)

# Create the Redis secret with real values
kubectl create secret generic redis-secret \
  --namespace aks-journal-app \
  --from-literal=REDIS_HOST="$REDIS_HOST" \
  --from-literal=REDIS_PORT="$REDIS_PORT" \
  --from-literal=REDIS_PASSWORD="$REDIS_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

# Deploy journal app (image substitution)
sed "s|\${AZURE_CONTAINER_REGISTRY}|${ACR_LOGIN_SERVER}|g; s|\${IMAGE_TAG}|${IMAGE_TAG}|g" \
  "$REPO_DIR/k8s/deployment.yaml" | kubectl apply -f -

kubectl apply -f "$REPO_DIR/k8s/service.yaml"
kubectl apply -f "$REPO_DIR/k8s/hpa.yaml"
kubectl apply -f "$REPO_DIR/k8s/pdb.yaml"

# Deploy MongoDB (in-cluster, no Azure service dependency)
echo "=== Deploying MongoDB ==="
kubectl apply -f "$REPO_DIR/k8s/mongodb.yaml"

# Deploy order-processor (image substitution)
echo "=== Deploying order-processor ==="
sed "s|\${AZURE_CONTAINER_REGISTRY}|${ACR_LOGIN_SERVER}|g; s|\${IMAGE_TAG}|${IMAGE_TAG}|g" \
  "$REPO_DIR/k8s/order-processor.yaml" | kubectl apply -f -

echo "=== Waiting for rollouts ==="
kubectl rollout status deployment/aks-journal -n aks-journal-app --timeout=120s
kubectl rollout status deployment/mongodb -n aks-journal-app --timeout=120s
kubectl rollout status deployment/order-processor -n aks-journal-app --timeout=120s

echo "=== Getting service external IP ==="
echo "Waiting for LoadBalancer IP..."
for i in {1..30}; do
  IP=$(kubectl get svc aks-journal -n aks-journal-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [ -n "$IP" ]; then
    echo "Journal app: http://${IP}"
    break
  fi
  sleep 5
done

echo ""
echo "=== Deployment complete ==="
echo "Pods:"
kubectl get pods -n aks-journal-app
