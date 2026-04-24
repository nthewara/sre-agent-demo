#!/bin/bash
set -euo pipefail

# Usage: ./scripts/inject-fault.sh <fault-number> [redis-host]
# Applies a fault scenario from the faults/ directory

if [ $# -lt 1 ]; then
  echo "Usage: $0 <fault-number> [redis-host]"
  echo ""
  echo "Fault scenarios:"
  echo "  1  Redis credential expiry (requires redis-host arg)"
  echo "  2  CPU starvation"
  echo "  3  OOM kill"
  echo "  4  CrashLoop (bad entrypoint)"
  echo "  5  ImagePullBackOff"
  echo "  6  Pending pods (insufficient resources)"
  echo "  7  Probe failure"
  echo "  8  Missing ConfigMap"
  echo "  9  Service selector mismatch"
  echo " 10  Network block (deny all egress)"
  echo " 11  MongoDB down (cascading dependency failure)"
  exit 1
fi

FAULT_NUM="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
NAMESPACE="aks-journal-app"
DEPLOYMENT="aks-journal"

get_current_image() {
  kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}'
}

store_healthy_image() {
  local current_image
  current_image="$(get_current_image)"

  if [ -z "$current_image" ]; then
    echo "Error: Unable to determine the currently deployed image for $DEPLOYMENT"
    exit 1
  fi

  kubectl create configmap sre-demo-state \
    --namespace "$NAMESPACE" \
    --from-literal=HEALTHY_IMAGE="$current_image" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
}

get_broken_image() {
  local current_image last_segment
  current_image="$(get_current_image)"
  last_segment="${current_image##*/}"

  if [[ "$current_image" == *@* ]]; then
    echo "${current_image%@*}:does-not-exist"
  elif [[ "$last_segment" == *:* ]]; then
    echo "${current_image%:*}:does-not-exist"
  else
    echo "${current_image}:does-not-exist"
  fi
}

apply_templated_fault() {
  local file current_image broken_image redis_host="${1:-}"
  file="$2"

  current_image="$(get_current_image)"
  broken_image="$(get_broken_image)"

  sed \
    -e "s|\${CURRENT_IMAGE}|${current_image}|g" \
    -e "s|\${BROKEN_IMAGE}|${broken_image}|g" \
    -e "s|\${REDIS_HOST}|${redis_host}|g" \
    "$file" | kubectl apply -f -
}

store_healthy_image

case "$FAULT_NUM" in
  1)
    REDIS_HOST="${2:?Error: Redis host required for fault 01. Usage: $0 1 <redis-host>}"
    echo "=== Injecting Fault 01: Redis Credential Expiry ==="
    apply_templated_fault "$REDIS_HOST" "$REPO_DIR/faults/01-redis-credential-expiry.yaml"
    echo "Recycling pods to pick up new secret..."
    kubectl delete pods -n "$NAMESPACE" -l app=aks-journal
    ;;
  2)
    echo "=== Injecting Fault 02: CPU Starvation ==="
    apply_templated_fault "" "$REPO_DIR/faults/02-cpu-starvation.yaml"
    ;;
  3)
    echo "=== Injecting Fault 03: OOM Kill ==="
    apply_templated_fault "" "$REPO_DIR/faults/03-oom-kill.yaml"
    ;;
  4)
    echo "=== Injecting Fault 04: CrashLoop ==="
    apply_templated_fault "" "$REPO_DIR/faults/04-crashloop.yaml"
    ;;
  5)
    echo "=== Injecting Fault 05: ImagePullBackOff ==="
    apply_templated_fault "" "$REPO_DIR/faults/05-image-pull-backoff.yaml"
    ;;
  6)
    echo "=== Injecting Fault 06: Pending Pods ==="
    kubectl apply -f "$REPO_DIR/faults/06-pending-pods.yaml"
    ;;
  7)
    echo "=== Injecting Fault 07: Probe Failure ==="
    apply_templated_fault "" "$REPO_DIR/faults/07-probe-failure.yaml"
    ;;
  8)
    echo "=== Injecting Fault 08: Missing ConfigMap ==="
    apply_templated_fault "" "$REPO_DIR/faults/08-missing-config.yaml"
    ;;
  9)
    echo "=== Injecting Fault 09: Service Selector Mismatch ==="
    kubectl apply -f "$REPO_DIR/faults/09-service-mismatch.yaml"
    ;;
  10)
    echo "=== Injecting Fault 10: Network Block ==="
    kubectl apply -f "$REPO_DIR/faults/10-network-block.yaml"
    ;;
  11)
    echo "=== Injecting Fault 11: MongoDB Down ==="
    kubectl apply -f "$REPO_DIR/faults/11-mongodb-down.yaml"
    echo "MongoDB scaled to 0 replicas. Order-processor readiness will degrade within ~15s."
    ;;
  *)
    echo "Error: Unknown fault number '$FAULT_NUM'. Valid: 1-11"
    exit 1
    ;;
esac

echo ""
echo "Fault injected. Wait 5-10 minutes for alerts to fire."
echo "Monitor at: https://sre.azure.com"
echo "Restore with: ./scripts/restore.sh <resource-group> <redis-name>"
