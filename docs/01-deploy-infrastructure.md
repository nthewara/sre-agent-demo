# Deploy Infrastructure

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) >= 2.50
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Docker](https://docs.docker.com/get-docker/)
- An Azure subscription with Contributor access
- Access to the shared Key Vault (for secrets)

## Step 1: Configure Variables

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your real values
```

## Step 2: Initialise Terraform

```bash
terraform init -backend-config=~/workspace/tfvars/backend.hcl
```

## Step 3: Plan

```bash
terraform plan -var-file=~/workspace/tfvars/sre-agent-demo.tfvars -out=tfplan
```

Review the plan. Expected resources:
- 1 Resource Group
- 1 Log Analytics Workspace
- 1 Container Registry (Basic)
- 1 AKS Cluster (3 nodes)
- 1 Redis Cache (Basic C0)
- 1 Action Group + 11 Alert Rules
- Diagnostic settings for AKS and Redis
- AcrPull role assignment

## Step 4: Apply

```bash
terraform apply tfplan
```

This takes approximately 10-15 minutes (Redis and AKS are the slow ones).

## Step 5: Build and Deploy the App

```bash
# Get outputs
RG=$(terraform output -raw resource_group_name)
ACR=$(terraform output -raw acr_name)
AKS=$(terraform output -raw aks_cluster_name)

# Deploy
cd ..
./scripts/deploy-app.sh "$RG" "$ACR" "$AKS"
```

## Step 6: Verify

```bash
# Check pods are running
kubectl get pods -n aks-journal-app

# Check service has external IP
kubectl get svc -n aks-journal-app

# Test the health endpoint
APP_IP=$(kubectl get svc aks-journal -n aks-journal-app -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl "http://${APP_IP}/health"
```

Expected output:
```json
{"status":"healthy","timestamp":"...","checks":{"redis":"connected"}}
```

## Next Steps

- [Set up SRE Agent](02-setup-sre-agent.md)
- [Run demo scenarios](03-demo-scenarios.md)
