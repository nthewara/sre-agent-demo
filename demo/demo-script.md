# Demo Script — Azure SRE Agent with AKS

**Duration:** 30-45 minutes (including setup verification)

---

## Pre-Demo Checklist (Do Before the Audience Arrives)

- [ ] Infrastructure deployed (`terraform apply` complete)
- [ ] App running and healthy (`curl http://<IP>/health`)
- [ ] SRE Agent configured at [sre.azure.com](https://sre.azure.com)
- [ ] Terminal windows ready:
  - Terminal 1: kubectl commands
  - Terminal 2: Load generator
  - Terminal 3: `watch kubectl get pods -n aks-journal-app`
- [ ] SRE Agent dashboard open in browser
- [ ] Azure Monitor alerts page open in another tab

---

## Part 1: Introduction (5 min)

**Talking points:**
- "Azure SRE Agent is an AI-powered agent that automatically investigates Kubernetes incidents"
- "It monitors Azure Monitor alerts and uses AI to correlate logs, metrics, and events"
- "Today we'll break things on purpose and watch it diagnose the problems"

**Show:**
- The running app (hit `/health` in the browser)
- The SRE Agent dashboard
- The alert rules in Azure Monitor

---

## Part 2: Scenario 1 — Redis Credential Expiry (10 min)

**Talking points:**
- "Imagine a Redis key rotation happened but nobody updated the Kubernetes secret"
- "This is one of the most common real-world incidents"

**Commands:**
```bash
# Show healthy state
curl http://<APP_IP>/health

# Inject the fault
./scripts/inject-fault.sh 1 <redis-host>

# Watch pods restart
kubectl get pods -n aks-journal-app -w

# Show degraded health
curl http://<APP_IP>/health
```

**Wait for alerts** (5-10 min) — fill time by explaining:
- How Container Insights collects logs
- What the KQL queries in the alert rules look for
- How SRE Agent receives the alert via the action group

**Show SRE Agent investigation** when it appears.

**Restore:**
```bash
./scripts/restore.sh <RG> <redis-name>
```

---

## Part 3: Scenario 3 — OOM Kill (10 min)

> Skip to scenario 3 for the most dramatic effect — OOMKill is immediate and visual.

**Talking points:**
- "Someone deployed with a 20Mi memory limit. Node.js needs at least 60Mi to start."
- "The kernel will kill this container instantly."

**Commands:**
```bash
./scripts/inject-fault.sh 3

# Watch the OOMKills happen
kubectl get pods -n aks-journal-app -w
kubectl describe pod -n aks-journal-app -l app=aks-journal | grep -A2 "Last State"
```

**Show SRE Agent investigation** — highlight how it correlates:
- OOMKilled events
- Memory working set metrics
- Deployment spec memory limits

**Restore:**
```bash
kubectl apply -f k8s/deployment.yaml
```

---

## Part 4: Wrap Up (5 min)

**Talking points:**
- "SRE Agent can investigate across logs, metrics, and K8s events simultaneously"
- "It reduces MTTR by doing the first 15 minutes of investigation automatically"
- "Currently in preview — try it at sre.azure.com"
- "Works with Azure Monitor alerts — no agent installation needed"

**Resources to share:**
- [sre.azure.com](https://sre.azure.com)
- [Documentation](https://learn.microsoft.com/en-us/azure/sre-agent/)
- [Tech Community Blog](https://techcommunity.microsoft.com/blog/azuredevcommunityblog/azure-sre-agent/4404642)
- This repo: `github.com/nthewara/sre-agent-demo`

---

## Backup Scenarios (If Time Permits)

### Scenario 2: CPU Starvation
```bash
./scripts/inject-fault.sh 2
# Watch pods fail to start
kubectl apply -f k8s/deployment.yaml  # restore
```

### Scenario 4: CrashLoop
```bash
./scripts/inject-fault.sh 4
kubectl logs -n aks-journal-app -l app=aks-journal --tail=5
# Shows MODULE_NOT_FOUND
kubectl apply -f k8s/deployment.yaml  # restore
```

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Alerts not firing | Check Container Insights is enabled; wait 10 min for data ingestion |
| SRE Agent not picking up alerts | Verify action group webhook is configured |
| Pods stuck terminating | `kubectl delete pods -n aks-journal-app --force --grace-period=0 -l app=aks-journal` |
| Load generator failing | Check the service external IP: `kubectl get svc -n aks-journal-app` |
