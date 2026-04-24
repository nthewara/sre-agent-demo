# Azure SRE Agent Demo — AKS Journal App

Demonstrate [Azure SRE Agent](https://sre.azure.com) investigating and diagnosing Kubernetes incidents in real time using a purpose-built journal application with fault injection scenarios.

```
┌─────────────────────────────────────────────────────────────────┐
│                        Azure Monitor                            │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────────────┐ │
│  │ Metric Alerts │  │  Log Alerts  │  │    Action Group       │ │
│  │ (CPU/Mem/Pod) │  │  (KQL-based) │  │ → Email + SRE Agent   │ │
│  └──────┬───────┘  └──────┬───────┘  └───────────┬───────────┘ │
│         │                 │                       │             │
│         └─────────┬───────┘                       │             │
│                   ▼                               ▼             │
│         ┌─────────────────┐             ┌─────────────────┐     │
│         │  Log Analytics   │             │  Azure SRE Agent│     │
│         │   Workspace      │◄────────────│  (AI Diagnosis) │     │
│         └────────┬────────┘             └─────────────────┘     │
│                  │                                              │
└──────────────────┼──────────────────────────────────────────────┘
                   │
    ┌──────────────┼──────────────┐
    │         AKS Cluster         │
    │  ┌───────────────────────┐  │
    │  │  aks-journal-app ns   │  │
    │  │  ┌─────┐ ┌─────┐     │  │
    │  │  │Pod 1│ │Pod 2│ ... │  │
    │  │  └──┬──┘ └──┬──┘     │  │
    │  │     └───┬───┘        │  │
    │  │         ▼            │  │
    │  │  ┌────────────┐      │  │
    │  │  │ Redis Cache │      │  │
    │  │  │  (Basic C0) │      │  │
    │  │  └────────────┘      │  │
    │  └───────────────────────┘  │
    │  Container Insights (OMS)   │
    └─────────────────────────────┘
```

## What This Demo Shows

This repo now includes **11 demo scenarios** covering both obvious failures and more subtle misconfigurations:

1. **Redis Credential Expiry** — bad Redis password, readiness degradation
2. **CPU Starvation** — tiny CPU limits, throttling, restarts
3. **OOM Kill** — memory limit too low for Node.js startup
4. **CrashLoop** — invalid entrypoint / immediate container failure
5. **ImagePullBackOff** — broken image tag
6. **Pending Pods** — unschedulable workloads due to oversized requests
7. **Probe Failure** — liveness/readiness paths misconfigured
8. **Missing ConfigMap** — CreateContainerConfigError from missing config reference
9. **Service Selector Mismatch** — healthy pods, zero service endpoints
10. **Network Block** — deny-all egress isolates the app from Redis
11. **MongoDB Down** — in-cluster MongoDB scaled to 0, order-processor cascading failure

These additional scenarios make the demo better for showing that SRE Agent can handle not just crashes, but also scheduling, service wiring, config drift, and network policy issues.

## Prerequisites

- Azure subscription with Contributor access
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) >= 2.50
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Docker](https://docs.docker.com/get-docker/)

## Quick Start

```bash
# 1. Clone
git clone https://github.com/nthewara/sre-agent-demo.git
cd sre-agent-demo

# 2. Deploy infrastructure (~15 min)
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init -backend-config=~/workspace/tfvars/backend.hcl
terraform plan -var-file=~/workspace/tfvars/sre-agent-demo.tfvars
terraform apply -var-file=~/workspace/tfvars/sre-agent-demo.tfvars

# 3. Deploy the app
cd ..
RG=$(cd terraform && terraform output -raw resource_group_name)
ACR=$(cd terraform && terraform output -raw acr_name)
AKS=$(cd terraform && terraform output -raw aks_cluster_name)
./scripts/deploy-app.sh "$RG" "$ACR" "$AKS"

# 4. Verify
APP_IP=$(kubectl get svc aks-journal -n aks-journal-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl "http://${APP_IP}/health"

# 5. Set up SRE Agent at https://sre.azure.com
# See docs/02-setup-sre-agent.md

# 6. Inject a fault and watch SRE Agent investigate
./scripts/inject-fault.sh 1 $(cd terraform && terraform output -raw redis_hostname)
```

## Demo Scenarios

| # | Scenario | Fault | Key Signals | SRE Agent Action |
|---|----------|-------|-------------|------------------|
| 1 | Redis Credential Expiry | Wrong Redis password | Redis errors, readiness failures | Finds WRONGPASS and points to secret drift |
| 2 | CPU Starvation | 5m CPU limit | Throttling, restarts, backoff | Correlates resource limits to startup failures |
| 3 | OOM Kill | 20Mi memory limit | OOMKilled, restarts | Recommends higher memory limits |
| 4 | CrashLoop | Bad entrypoint | Container errors, restarts | Reads logs, identifies bad command |
| 5 | ImagePullBackOff | Non-existent image tag | Failed pulls, ImagePullBackOff | Finds invalid image reference |
| 6 | Pending Pods | 32Gi / 8 CPU requests | FailedScheduling, Pending pods | Compares requests vs cluster capacity |
| 7 | Probe Failure | Bad health probe paths | Probe failures, restarts | Identifies broken probe config |
| 8 | Missing ConfigMap | Invalid envFrom reference | CreateContainerConfigError | Finds missing config object |
| 9 | Service Mismatch | Wrong selector labels | No endpoints, failed requests | Compares selector vs pod labels |
| 10 | Network Block | Deny-all egress policy | Redis errors, degraded readiness | Detects restrictive NetworkPolicy |
| 11 | MongoDB Down | MongoDB scaled to 0 | Order-processor NotReady, connection errors | Traces cascading failure to 0-replica MongoDB |

See [docs/03-demo-scenarios.md](docs/03-demo-scenarios.md) for detailed walkthroughs.

## Fault Injection

```bash
# Inject a fault
./scripts/inject-fault.sh <number> [redis-host]

# Examples
./scripts/inject-fault.sh 1 $(cd terraform && terraform output -raw redis_hostname)
./scripts/inject-fault.sh 5
./scripts/inject-fault.sh 9

# Restore to healthy state
RG=$(cd terraform && terraform output -raw resource_group_name)
REDIS=$(cd terraform && terraform output -raw redis_name)
./scripts/restore.sh "$RG" "$REDIS"
```

> The inject script now captures the currently healthy image before mutating the deployment, so restore can safely recover even from `ImagePullBackOff` scenarios.

## Documentation

- [Deploy Infrastructure](docs/01-deploy-infrastructure.md)
- [Set Up SRE Agent](docs/02-setup-sre-agent.md)
- [Demo Scenarios](docs/03-demo-scenarios.md)
- [Cleanup](docs/04-cleanup.md)
- [Fault Injection Details](faults/README.md)
- [Presenter Demo Script](demo/demo-script.md)

## Cost Estimate

| Resource | SKU | Cost/Day |
|----------|-----|----------|
| AKS (3× Standard_D2s_v5) | Pay-as-you-go | ~$7.20 |
| Redis Cache | Basic C0 | ~$0.53 |
| Log Analytics | PerGB2018 | ~$0.50 |
| Container Registry | Basic | ~$0.17 |
| **Total** | | **~$8.40/day** |

> 💡 Stop AKS when not in use: `az aks stop --resource-group <rg> --name <aks>`

## Cleanup

```bash
cd terraform
terraform destroy -var-file=~/workspace/tfvars/sre-agent-demo.tfvars
```

See [docs/04-cleanup.md](docs/04-cleanup.md) for full cleanup steps.

## References

- [Azure SRE Agent Portal](https://sre.azure.com)
- [Azure SRE Agent Documentation](https://learn.microsoft.com/en-us/azure/sre-agent/)
- [Tech Community Blog — Azure SRE Agent](https://techcommunity.microsoft.com/blog/azuredevcommunityblog/azure-sre-agent/4404642)
- [Azure Monitor Container Insights](https://learn.microsoft.com/en-us/azure/azure-monitor/containers/container-insights-overview)

## License

MIT
