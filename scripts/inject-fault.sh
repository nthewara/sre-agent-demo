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
  exit 1
fi

FAULT_NUM="$1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

case "$FAULT_NUM" in
  1)
    REDIS_HOST="${2:?Error: Redis host required for fault 01. Usage: $0 1 <redis-host>}"
    echo "=== Injecting Fault 01: Redis Credential Expiry ==="
    sed "s|\${REDIS_HOST}|${REDIS_HOST}|g" "$REPO_DIR/faults/01-redis-credential-expiry.yaml" | kubectl apply -f -
    echo "Recycling pods to pick up new secret..."
    kubectl delete pods -n aks-journal-app -l app=aks-journal
    ;;
  2)
    echo "=== Injecting Fault 02: CPU Starvation ==="
    kubectl apply -f "$REPO_DIR/faults/02-cpu-starvation.yaml"
    ;;
  3)
    echo "=== Injecting Fault 03: OOM Kill ==="
    kubectl apply -f "$REPO_DIR/faults/03-oom-kill.yaml"
    ;;
  4)
    echo "=== Injecting Fault 04: CrashLoop ==="
    kubectl apply -f "$REPO_DIR/faults/04-crashloop.yaml"
    ;;
  *)
    echo "Error: Unknown fault number '$FAULT_NUM'. Valid: 1-4"
    exit 1
    ;;
esac

echo ""
echo "Fault injected. Wait 5-10 minutes for alerts to fire."
echo "Monitor at: https://sre.azure.com"
echo "Restore with: ./scripts/restore.sh <resource-group> <redis-name>"
