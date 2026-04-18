# Cleanup

## Step 1: Delete Kubernetes Resources

```bash
kubectl delete namespace aks-journal-app
```

## Step 2: Delete SRE Agent

1. Go to [sre.azure.com](https://sre.azure.com)
2. Select your agent
3. Click **Delete**

## Step 3: Destroy Infrastructure

```bash
cd terraform
terraform destroy -var-file=~/workspace/tfvars/sre-agent-demo.tfvars
```

Type `yes` to confirm. This takes approximately 5-10 minutes.

## Step 4: Verify

```bash
# Confirm resource group is gone
az group show --name "rg-sreagent-XXXX" 2>&1 | grep -q "not found" && echo "Cleaned up"
```

## Cost Note

If you're not destroying immediately, **deallocate** to reduce costs:

```bash
# Stop AKS (stops billing for VMs, keeps config)
az aks stop --resource-group "rg-sreagent-XXXX" --name "aks-sreagent-XXXX"

# Restart when needed
az aks start --resource-group "rg-sreagent-XXXX" --name "aks-sreagent-XXXX"
```

Redis Basic C0 costs ~$0.022/hr ($0.53/day) even when idle — consider deleting if not needed.
