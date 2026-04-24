# SRE Agent Knowledge Instructions for This Lab

Use this document as a persistent knowledge source for the Azure SRE Agent attached to the `sre-journal-app` demo.

Upload it in the SRE Agent portal via:

**Builder → Knowledge sources**

---

## AKS Write Operations in This Lab

### Kubectl Write Commands — ALWAYS Use AKS Run Command API

**Problem:** In this lab environment, `RunKubectlWriteCommand` is currently broken — it fails with:

```text
Value cannot be an empty string. (Parameter 'resourceId')
```

Do **not** attempt it first. It wastes time and produces a confusing dead end.

### Solution — Go directly to AKS Run Command API via `ExecutePythonCode`

Always use the ARM **AKS Run Command API** for any kubectl **write** operation:

- scale
- patch
- apply
- label
- annotate
- rollout undo / restart
- set image
- set resources

This is the only reliable remediation path observed in this lab.

### Tool Selection Order for AKS Write Operations

1. **Always use AKS Run Command API via `ExecutePythonCode`** for AKS write actions.
2. **Do NOT use `RunKubectlWriteCommand`** in this lab — it fails with the `resourceId` error.
3. **Do NOT attempt**:
   - installing kubectl in terminal
   - `az aks command invoke`
   - direct Kubernetes API calls with managed identity

### Preferred Behaviour During Investigations

For AKS incidents in namespace `aks-journal-app`:

1. Use read tools first to identify the exact failure.
2. For any required write/remediation, use **AKS Run Command API via `ExecutePythonCode`**.
3. After remediation, always verify using:
   - `kubectl get pods -n aks-journal-app`
   - `kubectl get deploy -n aks-journal-app`
   - app health/readiness checks where relevant

---

## App Context

This is a Node.js journal application running on AKS.

- **Namespace:** `aks-journal-app`
- **Main app:** `aks-journal`
- **Background worker:** `order-processor`
- **Database:** `mongodb`
- **Redis:** external Azure Cache for Redis

### Health Endpoints

- `/health` — full health check
- `/ready` — readiness
- `/live` — liveness
- `/metrics` — app/runtime metrics

### Investigation Hints

- Check pod health, restart counts, events, rollout state, and logs.
- Check MongoDB availability for `order-processor` readiness failures.
- Check Redis connectivity and secret/config drift for app health degradation.
- Check image tags for `ImagePullBackOff`.
- Check resource limits for `OOMKilled` / `CrashLoopBackOff`.
- Check services, selectors, endpoints, and probe failures for traffic issues.

---

## Incident History / Known Patterns

| Date | Component | Symptom | Root Cause | Successful Fix |
|---|---|---|---|---|
| 2026-04-24 | `order-processor` | `CrashLoopBackOff`, `OOMKilled` (exit 137) | Memory limit reduced from `256Mi` to `20Mi` | Restore resources to `limits.memory=256Mi`, `requests.memory=128Mi` |
| 2026-04-24 | `mongodb` | Scaled to `0` replicas → `order-processor` readiness `503`, logs show `MongoDB connection lost` | `mongodb` deployment scaled to 0 | Scale `mongodb` back to `1` replica via AKS Run Command API |
| 2026-04-24 | `order-processor` | `ImagePullBackOff` | Bad image tag (`totally-fake-tag-v999`) | Roll back deployment to previous working revision |

---

## Verification Standard

Do not stop at diagnosis.

A successful investigation in this lab should usually end with:

1. Root cause identified
2. Fix executed using the correct write path
3. Recovery verified
4. Short summary of cause + remediation + verification

---

Updated: 2026-04-24 07:07 UTC
