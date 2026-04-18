# Set Up Azure SRE Agent

Azure SRE Agent uses AI to automatically investigate and help resolve Kubernetes incidents detected by Azure Monitor.

## Step 1: Navigate to SRE Agent Portal

Go to [https://sre.azure.com](https://sre.azure.com) and sign in with your Azure account.

## Step 2: Create a New SRE Agent

1. Click **+ Create Agent**
2. Select your **subscription** and the **resource group** created by Terraform
3. Select the **AKS cluster** as the target resource
4. Give the agent a name, e.g., `sre-journal-app`

## Step 3: Configure Incident Platform

1. Under **Incident Platform**, select **Azure Monitor**
2. Select the **Action Group** created by Terraform (`ag-sre-alerts-*`)
3. The agent will automatically monitor alerts from this action group

## Step 4: Set Up Action Group Webhook (Optional)

To get real-time incident creation, add the SRE Agent webhook to the action group:

1. In Azure Portal, navigate to **Monitor → Action Groups**
2. Edit the SRE alerts action group
3. Add a **Webhook** receiver with the URL provided by SRE Agent
4. Save

## Step 5: Add GitHub Connector (Optional)

If you want SRE Agent to create GitHub issues or PRs:

1. In the SRE Agent settings, go to **Connectors**
2. Click **+ Add GitHub**
3. Authorise access to your repository (`nthewara/sre-agent-demo`)
4. Select permissions: Issues (read/write), Pull Requests (read/write)

## Step 6: Configure Custom Instructions

Add context-specific instructions to help SRE Agent investigate more effectively:

```
This is a Node.js journal application running on AKS with Azure Cache for Redis.

Key debugging paths:
- Redis connection issues: Check the redis-secret in namespace aks-journal-app
- OOMKilled: Check deployment memory limits vs actual usage
- CPU throttling: Check deployment CPU limits
- CrashLoopBackOff: Check container logs and pod events

The app has three health endpoints:
- /health - Full health check including Redis
- /ready - Readiness (Redis connected)
- /live - Liveness (always 200 if process is running)

Namespace: aks-journal-app
Deployment: aks-journal
Service: aks-journal (LoadBalancer on port 80)
```

## Step 7: Verify Setup

1. Check the SRE Agent dashboard shows your AKS cluster as monitored
2. Verify the action group is connected
3. Optionally trigger a test alert to confirm end-to-end flow

## References

- [Azure SRE Agent documentation](https://learn.microsoft.com/en-us/azure/sre-agent/)
- [SRE Agent Portal](https://sre.azure.com)
- [Tech Community Blog Post](https://techcommunity.microsoft.com/blog/azuredevcommunityblog/azure-sre-agent/4404642)
