# Fault Injection Scenarios

This directory contains fault injection manifests for demonstrating Azure SRE Agent's automated incident response capabilities.

## Scenarios

### 01 — Redis Credential Expiry

**File:** `01-redis-credential-expiry.yaml`

**What it does:** Overwrites the `redis-secret` Kubernetes Secret with an intentionally wrong Redis password (`WRONG_EXPIRED_KEY_12345`), simulating a Redis key rotation where the application wasn't updated.

**What breaks:**
- Redis authentication fails with `WRONGPASS` errors
- App health checks return `503 degraded`
- Readiness probes fail → pods marked NotReady

**Alerts that fire:**
- Redis Connection Errors (Sev 1)
- Probe Failures (Sev 2)
- Pods Not Ready (Sev 1)
- Container Errors (Sev 2)

**Expected SRE Agent behaviour:**
1. Detects Redis `WRONGPASS` errors in container logs
2. Correlates with the `redis-secret` Kubernetes Secret
3. Suggests updating the secret with current Redis access keys
4. May recommend rolling restart after secret update

---

### 02 — CPU Starvation

**File:** `02-cpu-starvation.yaml`

**What it does:** Redeploys the app with a CPU limit of `5m` (5 millicores) — far too low for Node.js to start.

**What breaks:**
- Container can't complete startup within probe deadlines
- Massive CPU throttling
- Pods enter CrashLoopBackOff

**Alerts that fire:**
- High CPU (Sev 2)
- Pod Restarts (Sev 3)
- Probe Failures (Sev 2)
- BackOff Events (Sev 1)

**Expected SRE Agent behaviour:**
1. Identifies CPU throttling from Container Insights metrics
2. Correlates with the deployment's resource limits
3. Recommends increasing CPU limits (e.g., to 500m)

---

### 03 — OOM Kill

**File:** `03-oom-kill.yaml`

**What it does:** Redeploys the app with a memory limit of `20Mi` — Node.js needs ~60-80Mi minimum.

**What breaks:**
- Container gets OOMKilled by the kernel immediately after startup
- Pods enter CrashLoopBackOff

**Alerts that fire:**
- OOMKilled (Sev 1)
- Pod Restarts (Sev 3)
- BackOff Events (Sev 1)
- Pods Not Ready (Sev 1)

**Expected SRE Agent behaviour:**
1. Finds OOMKilled events in KubeEvents
2. Checks container memory working set vs limits
3. Recommends increasing memory limits (e.g., to 512Mi)

---

### 04 — CrashLoop (Bad Entrypoint)

**File:** `04-crashloop.yaml`

**What it does:** Overrides the container command to `node src/nonexistent-file.js`, causing immediate exit with `MODULE_NOT_FOUND`.

**What breaks:**
- Container exits instantly on every start
- Kubernetes restarts it, entering CrashLoopBackOff

**Alerts that fire:**
- Pod Restarts (Sev 3)
- BackOff Events (Sev 1)
- Container Errors (Sev 2)
- Pods Not Ready (Sev 1)

**Expected SRE Agent behaviour:**
1. Reads container logs showing `MODULE_NOT_FOUND` error
2. Identifies the bad `command` override in the deployment spec
3. Recommends removing the command override or reverting to the previous deployment

---

## How to Use

```bash
# Inject a specific fault
./scripts/inject-fault.sh <number> [redis-host]

# Example: inject fault 01
./scripts/inject-fault.sh 1 myredis.redis.cache.windows.net

# Restore to healthy state
./scripts/restore.sh <resource-group> <redis-name>
```

## Tips

- Wait 5-10 minutes after injecting a fault for alerts to fire
- Use `./scripts/load-generator.sh` to increase traffic and accelerate alert triggers
- Monitor the SRE Agent dashboard at [sre.azure.com](https://sre.azure.com) for automated investigations
