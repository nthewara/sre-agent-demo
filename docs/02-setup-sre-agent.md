# Set Up Azure SRE Agent

Azure SRE Agent uses AI to automatically investigate and help resolve Kubernetes incidents detected by Azure Monitor.

## Prerequisites

Before starting:
- Infrastructure deployed via Terraform (see [01-deploy-infrastructure.md](01-deploy-infrastructure.md))
- Access to [https://sre.azure.com](https://sre.azure.com)
- AKS credentials configured:
  ```bash
  az aks get-credentials \
    --resource-group <rg-name> \
    --name <aks-name> \
    --overwrite-existing
  ```
  If you switch clusters or see DNS lookup errors, re-run this to update `~/.kube/config`.

---

## Step 1: Navigate to SRE Agent Portal

Go to [https://sre.azure.com](https://sre.azure.com) and sign in with your Azure account.

## Step 2: Create a New SRE Agent

1. Click **+ Create Agent**
2. Select your **subscription** (`ME-MngEnvMCAP504427-nirmalt-1`) and **resource group** (`rg-sreagent-ppya`)
3. Give the agent a name, e.g., `sre-journal-app`
4. Click **Create**
5. Once deployment completes, click **Set up your agent**

## Step 3: Add Azure Resources

1. On the setup screen, click **+** next to **Azure resources**
2. When prompted for permissions, select **Privileged** (required for remediation actions — this is a demo RG)
3. Confirm/approve the RBAC role assignments
4. Resources to connect:
   - **Resource group:** `rg-sreagent-ppya`
   - **AKS cluster:** `aks-sreagent-ppya`
   - **Log Analytics workspace:** `law-sreagent-ppya`

> **Incidents** and **Code** are optional. Skip them for a quick start.

5. Click **Done and go to agent**

## Step 4: Provide Context to the Agent

Paste the following into the agent chat as your first message (this gives the agent context about the app):

```
Use this as context for all future investigations:

This is a Node.js journal application running on AKS.

Namespace: aks-journal-app
Main app: aks-journal
Background worker: order-processor
Database: mongodb
Redis cache is external Azure Cache for Redis.
Public endpoint: http://<EXTERNAL-IP>

Health endpoints:
- /health  — full health check (includes Redis)
- /ready   — readiness probe (Redis connected)
- /live    — liveness probe (always 200 if process running)

When investigating:
- Check pod health, restart counts, events, and logs
- Check Redis connectivity and secret/config drift
- Check MongoDB availability for order-processor issues
- Check service selectors, endpoints, and probe failures
- Focus on namespace: aks-journal-app
```

> Replace `<EXTERNAL-IP>` with the output of:
> ```bash
> kubectl get svc aks-journal -n aks-journal-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
> ```

## Step 5: Add Persistent Lab Instructions (Recommended)

In the SRE Agent portal, go to:

**Builder → Knowledge sources**

Upload this file from the repo:

```text
docs/05-sre-agent-knowledge.md
```

This gives the agent persistent lab-specific guidance, including the preferred AKS write-remediation path and known incident patterns.

## Step 6: Verify the Agent is Working

Ask the agent:

```
Run a health check on aks-journal-app
```

Expected response:
- Deployments: aks-journal 3/3, order-processor 2/2, mongodb 1/1 — all available, 0 restarts
- Services/endpoints: LoadBalancer with 3 endpoints, internal services populated
- Probes: /ready and /live returning 200
- Resources: CPU and memory within normal limits

## Step 7: Configure Action Group Webhook (Optional)

To get real-time incident creation when Azure Monitor alerts fire:

1. In Azure Portal, navigate to **Monitor → Action Groups**
2. Edit `ag-sre-alerts-ppya`
3. Add a **Webhook** receiver with the URL provided by SRE Agent
4. Save

## Step 8: Add GitHub Connector (Optional)

To let SRE Agent create GitHub issues or PRs for incidents:

1. In the SRE Agent settings, go to **Connectors**
2. Click **+ Add GitHub**
3. Authorise access to `nthewara/sre-agent-demo`
4. Permissions required: Issues (read/write), Pull Requests (read/write)

---

## Common Issues

### kubectl DNS errors / "no such host"
Your kubeconfig is pointing at an old cluster. Fix:
```bash
az aks get-credentials \
  --resource-group rg-sreagent-ppya \
  --name aks-sreagent-ppya \
  --overwrite-existing
```

### Agent can't see resources
Make sure the Privileged role assignments were approved in Step 3.
The SRE Agent's managed identity needs **Contributor** and **AKS Cluster Admin** on the RG.

### order-processor not ready after fresh deploy
This is a startup race — order-processor can fail to connect to MongoDB during initial pod scheduling.
Fix: wait for MongoDB to be fully running, then restart the deployment:
```bash
kubectl rollout restart deployment/order-processor -n aks-journal-app
```

---

## Running Demo Scenarios

Once the agent is set up and responding, break something and watch it investigate:

| Scenario | Break command | Restore command |
|----------|--------------|-----------------|
| MongoDB down (cascading failure) | `kubectl scale deployment mongodb -n aks-journal-app --replicas=0` | `kubectl scale deployment mongodb -n aks-journal-app --replicas=1` |
| OOMKilled | `./scripts/inject-fault.sh 3` | `./scripts/restore.sh <rg> <redis-name>` |
| CrashLoop | `./scripts/inject-fault.sh 4` | `./scripts/restore.sh <rg> <redis-name>` |
| Redis credential drift | `./scripts/inject-fault.sh 1 <redis-hostname>` | `./scripts/restore.sh <rg> <redis-name>` |
| ImagePullBackOff | `./scripts/inject-fault.sh 5` | `./scripts/restore.sh <rg> <redis-name>` |

After breaking, ask the agent:
```
Something feels off with the app. Can you investigate what's going wrong right now?
```

See [03-demo-scenarios.md](03-demo-scenarios.md) for full walkthroughs of all 11 scenarios.

---

## References

- [Azure SRE Agent documentation](https://learn.microsoft.com/en-us/azure/sre-agent/)
- [SRE Agent Portal](https://sre.azure.com)
- [Tech Community Blog Post](https://techcommunity.microsoft.com/blog/azuredevcommunityblog/azure-sre-agent/4404642)
