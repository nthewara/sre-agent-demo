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

## Environment Reference

- **Subscription:** `ME-MngEnvMCAP504427-nirmalt-1` (`b9d87a00-a4d8-47d9-84a2-cfd7a9d745d2`)
- **Resource group:** `rg-sreagent-ppya`
- **Region:** `australiaeast`
- **AKS cluster:** `aks-sreagent-ppya`
- **ACR:** `acrsreagentppya.azurecr.io`
- **Log Analytics workspace:** `law-sreagent-ppya`
- **Azure Cache for Redis:** `redis-sreagent-ppya`
- **Action Group:** `ag-sre-alerts-ppya`
- **App public endpoint:** `http://20.193.22.139`

Scope of automated action:

- Operate **only** within resource group `rg-sreagent-ppya` and namespace `aks-journal-app`.
- Never create/delete non-namespace-scoped resources without explicit human confirmation.
- Never modify RBAC, networking, node pools, or cluster-level config without explicit human confirmation.

---

## AKS Run Command API — Reference Pattern

When performing any AKS write action, use the ARM **Run Command** API via `ExecutePythonCode`. Template:

```python
import json, time, requests
from azure.identity import DefaultAzureCredential

SUBSCRIPTION = "b9d87a00-a4d8-47d9-84a2-cfd7a9d745d2"
RG           = "rg-sreagent-ppya"
CLUSTER      = "aks-sreagent-ppya"
API          = "2024-02-01"

# The kubectl command to run (example: scale mongodb back to 1)
COMMAND = "kubectl scale deployment mongodb -n aks-journal-app --replicas=1"

token = DefaultAzureCredential().get_token("https://management.azure.com/.default").token
headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}
base = (
    f"https://management.azure.com/subscriptions/{SUBSCRIPTION}"
    f"/resourceGroups/{RG}/providers/Microsoft.ContainerService/managedClusters/{CLUSTER}"
)

r = requests.post(f"{base}/runCommand?api-version={API}",
                  headers=headers, data=json.dumps({"command": COMMAND}))
op = r.headers.get("azure-asyncoperation") or r.headers.get("location")
while True:
    time.sleep(3)
    s = requests.get(op, headers=headers).json()
    if s.get("properties", {}).get("provisioningState") in ("Succeeded", "Failed", "Canceled") or s.get("status") in ("Succeeded", "Failed", "Canceled"):
        break

result_url = f"{base}/commandResults/{op.rstrip('/').split('/')[-1].split('?')[0]}?api-version={API}"
result = requests.get(result_url, headers=headers).json()
print(result.get("properties", {}).get("logs") or result)
```

Always print the logs back to the chat so the operator can see the actual `kubectl` output.

---

## Scenario Playbook (Preferred Remediations)

| Scenario | Signal | Preferred Remediation |
|---|---|---|
| Scaled to 0 replicas | `READY 0/0` on a deployment | `kubectl scale deployment <name> -n aks-journal-app --replicas=<previous>` |
| `ImagePullBackOff` / `ErrImagePull` | Bad/unknown tag in pod events | `kubectl rollout undo deployment/<name> -n aks-journal-app` |
| `CrashLoopBackOff` + `OOMKilled` (exit 137) | `Reason: OOMKilled` in `describe pod` | `kubectl set resources deployment/<name> -n aks-journal-app --limits=memory=256Mi --requests=memory=128Mi` **or** `rollout undo` |
| Readiness `503` only (pods `Running` but `0/N Ready`) | `/ready` 503, logs show dependency error | Restore the dependency (e.g. `kubectl scale deployment mongodb ... --replicas=1`), do NOT restart the app first |
| Redis connection failure | `/health` reports `redis: disconnected` | Check `redis-secret`; if rotated/wrong, reconcile from key vault / Azure Cache key, then `kubectl rollout restart deployment/aks-journal -n aks-journal-app` |
| Service targetPort mismatch | Endpoints empty, pods healthy | Restore `Service.spec.ports[].targetPort` to match container port |
| `Pending` pods | Insufficient cpu/memory | Reduce requests to last-known-good, or scale node pool (require human confirmation) |

---

## Guardrails — When NOT to Auto-Remediate

Investigate and propose, but **do not execute without human confirmation**, when any of these apply:

- The fix would **delete data** (PVCs, statefulset volumes, MongoDB deployment/PV).
- The fix would **change RBAC / identity / network policy / NSGs**.
- The fix requires **cordon/drain/delete of nodes** or node pool scaling.
- The fix needs **new Azure resources** to be created.
- The failure pattern has **no prior successful match** in this knowledge base and the blast radius is unclear.
- Multiple plausible root causes remain after diagnosis — propose the top two and ask.

In any of those cases, produce a clear recommended command block and ask for approval explicitly.

---

## Prompt / Response Style

When responding in chat:

1. **Start with a one-line TL;DR** of current state (e.g. “order-processor is CrashLooping due to 20Mi memory limit — OOMKilled x13”).
2. List the evidence used (tool + key output lines), not the full raw dump.
3. State the proposed fix in a single fenced code block.
4. Execute it via AKS Run Command API (unless guardrails above apply).
5. Verify, then give a short recovery summary.

Avoid:

- Filler like “Great question” / “I’d be happy to help”.
- Long retellings of what kubectl is.
- Proposing without checking — always verify current state before acting.

---

## Runbook Capture

After a successful investigation, save a runbook to **Knowledge sources** named:

```
runbook-<component>-<symptom>.md
```

Examples:

- `runbook-order-processor-oomkilled.md`
- `runbook-mongodb-scaled-to-zero.md`
- `runbook-order-processor-image-pull-backoff.md`

Each runbook should include:

1. Symptoms observed
2. Diagnostic commands that proved the root cause
3. Exact remediation executed
4. Verification evidence
5. Any follow-up actions (alerts, code fixes, guardrails)

---

## Escalation

Escalate to a human operator if:

- Two remediation attempts fail.
- The issue spans outside `aks-journal-app` namespace or `rg-sreagent-ppya`.
- The agent detects data loss, auth failures at ARM layer, or cluster-level degradation (API server errors, node NotReady).
- Cost or security implications are suspected.

---

Updated: 2026-04-24 07:50 UTC
