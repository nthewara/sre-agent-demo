# Fault Injection Scenarios

This directory contains fault injection manifests for demonstrating Azure SRE Agent's automated incident response capabilities.

## Scenarios

### 01 — Redis Credential Expiry

**File:** `01-redis-credential-expiry.yaml`

**What it does:** Overwrites the `redis-secret` Kubernetes Secret with an intentionally wrong Redis password, simulating a Redis key rotation where the application was not updated.

**Expected SRE Agent behaviour:**
1. Detects `WRONGPASS` errors in container logs
2. Correlates them with `redis-secret`
3. Suggests updating the secret with the current Redis access key

---

### 02 — CPU Starvation

**File:** `02-cpu-starvation.yaml`

**What it does:** Redeploys the app with a CPU limit of `5m`.

**Expected SRE Agent behaviour:**
1. Identifies CPU throttling from metrics
2. Correlates it with deployment resource limits
3. Recommends increasing CPU requests/limits

---

### 03 — OOM Kill

**File:** `03-oom-kill.yaml`

**What it does:** Redeploys the app with a memory limit of `20Mi`.

**Expected SRE Agent behaviour:**
1. Finds OOMKilled events
2. Checks memory working set versus limits
3. Recommends increasing memory limits

---

### 04 — CrashLoop (Bad Entrypoint)

**File:** `04-crashloop.yaml`

**What it does:** Overrides the container command to `node src/nonexistent-file.js`.

**Expected SRE Agent behaviour:**
1. Reads container logs showing `MODULE_NOT_FOUND`
2. Identifies the bad `command` override
3. Recommends reverting the deployment

---

### 05 — ImagePullBackOff

**File:** `05-image-pull-backoff.yaml`

**What it does:** Redeploys the app with a non-existent image tag.

**Expected SRE Agent behaviour:**
1. Reads image pull failure events
2. Identifies the invalid image reference
3. Recommends restoring the last known good image

---

### 06 — Pending Pods

**File:** `06-pending-pods.yaml`

**What it does:** Deploys oversized placeholder pods requesting `32Gi` memory and `8` CPU.

**Expected SRE Agent behaviour:**
1. Finds `FailedScheduling` events
2. Compares requests against node capacity
3. Recommends reducing requests or scaling the cluster

---

### 07 — Probe Failure

**File:** `07-probe-failure.yaml`

**What it does:** Redeploys the app with invalid liveness and readiness probe paths.

**Expected SRE Agent behaviour:**
1. Detects probe failures in pod events
2. Inspects the deployment health probe config
3. Recommends restoring valid probe paths

---

### 08 — Missing ConfigMap

**File:** `08-missing-config.yaml`

**What it does:** Redeploys the app with an envFrom reference to `journal-config-missing`.

**Expected SRE Agent behaviour:**
1. Finds `CreateContainerConfigError` and missing ConfigMap events
2. Locates the bad reference in the deployment spec
3. Recommends switching back to `journal-config`

---

### 09 — Service Selector Mismatch

**File:** `09-service-mismatch.yaml`

**What it does:** Changes the `aks-journal` service selectors so they no longer match healthy pods.

**Expected SRE Agent behaviour:**
1. Notices pods are healthy but traffic still fails
2. Checks service selectors and endpoints
3. Identifies the selector mismatch as the root cause

---

### 10 — Network Block

**File:** `10-network-block.yaml`

**What it does:** Applies a deny-all egress `NetworkPolicy` to the journal pods.

**Expected SRE Agent behaviour:**
1. Detects Redis connectivity failures and degraded readiness
2. Enumerates NetworkPolicies in the namespace
3. Identifies the restrictive egress policy

---

## How to Use

```bash
# Inject a specific fault
./scripts/inject-fault.sh <number> [redis-host]

# Examples
./scripts/inject-fault.sh 1 myredis.redis.cache.windows.net
./scripts/inject-fault.sh 5
./scripts/inject-fault.sh 10

# Restore to healthy state
RG=$(cd terraform && terraform output -raw resource_group_name)
REDIS=$(cd terraform && terraform output -raw redis_name)
./scripts/restore.sh "$RG" "$REDIS"
```

## Notes

- Run one scenario at a time
- Always restore before the next scenario
- `inject-fault.sh` stores the current healthy image so `restore.sh` can recover even after an `ImagePullBackOff`
- `restore.sh` also cleans up extra objects created by pending-pod and network-policy scenarios

---

### 11 — MongoDB Down (Cascading Dependency Failure)

**File:** `11-mongodb-down.yaml`

**What it does:** Scales the in-cluster `mongodb` deployment to 0 replicas.

**Expected SRE Agent behaviour:**
1. Detects that order-processor pods are NotReady but not crashing
2. Reads connection error logs from order-processor
3. Traces the dependency to the `mongodb` Kubernetes service
4. Finds 0 replicas on the `mongodb` deployment
5. Recommends scaling it back to 1

