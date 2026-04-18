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

### Alerts (within 5-10 min)

- ⚠️ Redis Connection Errors (Sev 1)
- ⚠️ Probe Failures (Sev 2)
- ⚠️ Pods Not Ready (Sev 1)

### Expected SRE Agent Investigation

<!-- Screenshot placeholder: SRE Agent investigation for Redis credential failure -->

1. Agent detects `WRONGPASS` in container logs
2. Correlates with Redis secret configuration
3. Recommends updating the `redis-secret` with valid Redis access keys

### Restore

```bash
RG=$(cd terraform && terraform output -raw resource_group_name)
./scripts/restore.sh "$RG" "redis-sreagent-XXXX"
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
2. Node.js can't initialise within probe timeouts
3. Pods enter CrashLoopBackOff
4. HPA may try to scale up (won't help)

### Alerts (within 5-10 min)

- ⚠️ High CPU (Sev 2)
- ⚠️ Pod Restarts (Sev 3)
- ⚠️ BackOff Events (Sev 1)

### Expected SRE Agent Investigation

<!-- Screenshot placeholder: SRE Agent investigation for CPU starvation -->

1. Agent identifies CPU throttling in Container Insights
2. Correlates with deployment resource spec
3. Recommends increasing CPU limits

### Restore

```bash
kubectl apply -f k8s/deployment.yaml
```

---

## Scenario 3: OOM Kill

**Story:** Memory limits were set too low (20Mi) for a Node.js application.

### Inject

```bash
./scripts/inject-fault.sh 3
```

### What Happens

1. Node.js starts, allocates >20Mi during import phase
2. Kernel OOMKills the container
3. Immediate restart → OOMKill → CrashLoopBackOff

### Alerts (within 5-10 min)

- 🔴 OOMKilled (Sev 1)
- ⚠️ Pod Restarts (Sev 3)
- 🔴 BackOff Events (Sev 1)

### Expected SRE Agent Investigation

<!-- Screenshot placeholder: SRE Agent investigation for OOMKill -->

1. Agent finds OOMKilled events in KubeEvents
2. Checks container memory working set vs limits
3. Recommends increasing memory limits to at least 128Mi

### Restore

```bash
kubectl apply -f k8s/deployment.yaml
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

### Alerts (within 5-10 min)

- ⚠️ Container Errors (Sev 2)
- ⚠️ Pod Restarts (Sev 3)
- 🔴 BackOff Events (Sev 1)

### Expected SRE Agent Investigation

<!-- Screenshot placeholder: SRE Agent investigation for CrashLoop -->

1. Agent reads container logs showing `MODULE_NOT_FOUND`
2. Identifies the `command` override in deployment spec
3. Recommends removing the command override or reverting the deployment

### Restore

```bash
kubectl apply -f k8s/deployment.yaml
```

---

## Tips

- Run scenarios one at a time and **always restore** before injecting the next fault
- The load generator helps alerts fire faster by generating more data points
- Check the SRE Agent dashboard at [sre.azure.com](https://sre.azure.com) for investigation timelines
- Container Insights data has a ~5 minute ingestion delay
