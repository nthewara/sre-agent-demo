# Demo Scenarios

Each scenario injects a specific fault, waits for Azure Monitor alerts to fire, and demonstrates SRE Agent's automated investigation capabilities.

## Before You Begin

Ensure the app is running healthy:
```bash
kubectl get pods -n aks-journal-app
# All 3 pods should be Running and Ready

APP_IP=$(kubectl get svc aks-journal -n aks-journal-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl "http://${APP_IP}/health"
# Should return {"status":"healthy"}
```

Start the load generator in a separate terminal:
```bash
./scripts/load-generator.sh "http://${APP_IP}"
```

---

## Scenario 1: Redis Credential Expiry

**Story:** A Redis key rotation occurred but the Kubernetes secret wasn't updated.

### Inject

```bash
REDIS_HOST=$(cd terraform && terraform output -raw redis_hostname)
./scripts/inject-fault.sh 1 "$REDIS_HOST"
```

### What Happens

1. Pods restart with new (wrong) Redis credentials
2. Health endpoint returns `{"status":"degraded"}`
3. Readiness probes fail → pods marked NotReady
4. Load generator requests start getting 503s

### Expected SRE Agent Investigation

1. Agent detects `WRONGPASS` in container logs
2. Correlates with Redis secret configuration
3. Recommends updating the `redis-secret` with valid Redis access keys

### Restore

```bash
RG=$(cd terraform && terraform output -raw resource_group_name)
REDIS=$(cd terraform && terraform output -raw redis_name)
./scripts/restore.sh "$RG" "$REDIS"
```

---

## Scenario 2: CPU Starvation

**Story:** A deployment config change accidentally set CPU limits to 5 millicores.

### Inject

```bash
./scripts/inject-fault.sh 2
```

### What Happens

1. Deployment rolls out with 5m CPU limit
2. Node.js cannot initialise within probe timeouts
3. Pods enter CrashLoopBackOff
4. HPA may try to scale up, but it will not fix throttling

### Expected SRE Agent Investigation

1. Agent identifies CPU throttling in Container Insights
2. Correlates with deployment resource spec
3. Recommends increasing CPU limits

### Restore

```bash
./scripts/restore.sh "$RG" "$REDIS"
```

---

## Scenario 3: OOM Kill

**Story:** Memory limits were set too low (20Mi) for a Node.js application.

### Inject

```bash
./scripts/inject-fault.sh 3
```

### What Happens

1. Node.js starts, allocates more than 20Mi during startup
2. Kernel OOMKills the container
3. Immediate restart → OOMKill → CrashLoopBackOff

### Expected SRE Agent Investigation

1. Agent finds OOMKilled events in KubeEvents
2. Checks container memory working set vs limits
3. Recommends increasing memory limits to at least 128Mi

### Restore

```bash
./scripts/restore.sh "$RG" "$REDIS"
```

---

## Scenario 4: CrashLoop (Bad Entrypoint)

**Story:** A deployment referenced a nonexistent file, causing immediate container exit.

### Inject

```bash
./scripts/inject-fault.sh 4
```

### What Happens

1. Container starts with `node src/nonexistent-file.js`
2. Node.js throws `MODULE_NOT_FOUND` and exits
3. Kubernetes restarts → same error → CrashLoopBackOff

### Expected SRE Agent Investigation

1. Agent reads container logs showing `MODULE_NOT_FOUND`
2. Identifies the `command` override in deployment spec
3. Recommends removing the command override or reverting the deployment

### Restore

```bash
./scripts/restore.sh "$RG" "$REDIS"
```

---

## Scenario 5: ImagePullBackOff

**Story:** A deployment update referenced a non-existent image tag.

### Inject

```bash
./scripts/inject-fault.sh 5
```

### What Happens

1. New pods are scheduled
2. Kubelet fails to pull the image
3. Pods remain in `ImagePullBackOff`

### What to Observe

```bash
kubectl get pods -n aks-journal-app
kubectl describe pod -n aks-journal-app -l app=aks-journal | grep -A 10 -E 'Failed|Pull|Image'
```

### Expected SRE Agent Investigation

1. Agent finds failed image pull events
2. Compares current deployment image to the known-good tag
3. Recommends reverting the image reference

### Restore

```bash
./scripts/restore.sh "$RG" "$REDIS"
```

---

## Scenario 6: Pending Pods

**Story:** A new workload was deployed with requests larger than any node in the cluster can satisfy.

### Inject

```bash
./scripts/inject-fault.sh 6
```

### What Happens

1. `resource-hog` pods are created
2. Scheduler cannot place them on any node
3. Pods remain `Pending`

### What to Observe

```bash
kubectl get pods -n aks-journal-app
kubectl describe pod -n aks-journal-app -l app=resource-hog | grep -A 10 FailedScheduling
```

### Expected SRE Agent Investigation

1. Agent inspects `FailedScheduling` events
2. Compares requested CPU/memory to node capacity
3. Recommends reducing resource requests or scaling the node pool

### Restore

```bash
./scripts/restore.sh "$RG" "$REDIS"
```

---

## Scenario 7: Probe Failure

**Story:** A deployment change pointed readiness and liveness probes to the wrong paths.

### Inject

```bash
./scripts/inject-fault.sh 7
```

### What Happens

1. Container process starts normally
2. Liveness and readiness probes hit invalid endpoints
3. Pods cycle through restarts and never become Ready

### What to Observe

```bash
kubectl get pods -n aks-journal-app
kubectl describe pod -n aks-journal-app -l app=aks-journal | grep -A 10 -E 'Liveness|Readiness'
```

### Expected SRE Agent Investigation

1. Agent identifies probe failures from events
2. Reads the deployment probe configuration
3. Recommends restoring `/live` and `/ready`

### Restore

```bash
./scripts/restore.sh "$RG" "$REDIS"
```

---

## Scenario 8: Missing ConfigMap

**Story:** A deployment started referencing a ConfigMap that was never created.

### Inject

```bash
./scripts/inject-fault.sh 8
```

### What Happens

1. Pods are created
2. Kubelet fails container setup because `journal-config-missing` does not exist
3. Pods show `CreateContainerConfigError`

### What to Observe

```bash
kubectl get pods -n aks-journal-app
kubectl describe pod -n aks-journal-app -l app=aks-journal | grep -A 10 -E 'ConfigMap|CreateContainerConfigError'
```

### Expected SRE Agent Investigation

1. Agent finds missing ConfigMap errors in events
2. Checks the deployment envFrom reference
3. Recommends restoring the valid `journal-config` reference

### Restore

```bash
./scripts/restore.sh "$RG" "$REDIS"
```

---

## Scenario 9: Service Selector Mismatch

**Story:** A service selector was changed during a refactor, but the pods were never relabeled.

### Inject

```bash
./scripts/inject-fault.sh 9
```

### What Happens

1. Pods remain healthy and Ready
2. The `aks-journal` service has zero endpoints
3. Requests to the app fail even though the deployment looks fine

### What to Observe

```bash
kubectl get pods -n aks-journal-app --show-labels
kubectl get endpoints -n aks-journal-app aks-journal aks-journal-internal
kubectl get svc -n aks-journal-app aks-journal -o jsonpath='{.spec.selector}'
```

### Expected SRE Agent Investigation

1. Agent sees that pod health is normal
2. Checks service selectors and endpoints
3. Identifies the selector mismatch as the real root cause

### Restore

```bash
./scripts/restore.sh "$RG" "$REDIS"
```

---

## Scenario 10: Network Block

**Story:** A security policy rollout accidentally denied all egress from the application pods.

### Inject

```bash
./scripts/inject-fault.sh 10
```

### What Happens

1. The journal pods keep running
2. They can no longer connect to Redis
3. `/health` becomes degraded and readiness fails

### What to Observe

```bash
kubectl get networkpolicy -n aks-journal-app
kubectl describe networkpolicy deny-all-egress -n aks-journal-app
curl "http://${APP_IP}/health"
```

### Expected SRE Agent Investigation

1. Agent detects Redis connectivity failures
2. Enumerates NetworkPolicies in the namespace
3. Identifies the deny-all egress rule as the breakage

### Restore

```bash
./scripts/restore.sh "$RG" "$REDIS"
```

---

## Demo Flow Suggestions

### Quick Demo (5-7 minutes)

1. Start with **OOM Kill** or **CrashLoop**
2. Show pods failing in `kubectl`
3. Ask SRE Agent for diagnosis
4. Restore and confirm the cluster recovers

### Intermediate Demo (10-15 minutes)

1. **ImagePullBackOff** — deployment/runtime issue
2. **Probe Failure** — config issue
3. **Pending Pods** — scheduler/capacity issue
4. **Restore** and show clean recovery

### Advanced Demo (15-20 minutes)

1. **Service Selector Mismatch** — subtle, healthy pods but broken traffic
2. **Network Block** — policy-related dependency failure
3. **Redis Credential Expiry** — secret drift / dependency auth failure
4. Ask SRE Agent to compare symptoms and root causes across the incidents

## Tips

- Run scenarios one at a time and always restore before the next one
- The load generator helps alerts fire faster by generating more data points
- Service mismatch and network policy demos are especially good for showing that not all incidents come from crashing pods
- The inject script saves the last known healthy image so restore still works after image-based failures
- Container Insights data usually has a small ingestion delay

---

## Scenario 11: MongoDB Down (Cascading Dependency Failure)

**Story:** The MongoDB deployment was accidentally scaled to zero during a "cost saving" change. The order-processor service keeps running but can no longer write or read orders.

### Inject

```bash
./scripts/inject-fault.sh 11
```

### What Happens

1. MongoDB is scaled to 0 replicas
2. The order-processor's ping loop detects connection loss within ~3s
3. `/ready` returns 503 → pods are marked NotReady
4. Existing journal app pods remain healthy (different dependency)

### What to Observe

```bash
# MongoDB has 0 replicas
kubectl get deployment mongodb -n aks-journal-app

# order-processor pods NotReady
kubectl get pods -n aks-journal-app

# Connection error logs
kubectl logs -n aks-journal-app -l app=order-processor --tail=20
```

### Expected SRE Agent Investigation

1. Agent notices order-processor pods are NotReady but not crashing
2. Reads container logs and finds "MongoDB not connected" errors
3. Checks the `MONGODB_URL` env var — resolves to in-cluster `mongodb` service
4. Finds that the `mongodb` deployment has 0 replicas
5. Recommends scaling MongoDB back to 1

**SRE Agent prompts:**
- "Why is order-processor NotReady but not crashing?"
- "Trace the dependency chain for the order-processor service"
- "What's preventing order-processor from becoming healthy?"
- "Scale the mongodb deployment back to 1 replica"

### Restore

```bash
./scripts/restore.sh "$RG" "$REDIS"
```

