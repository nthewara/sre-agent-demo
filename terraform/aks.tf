# --- AKS Cluster ---
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-${var.prefix}-${local.suffix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "${var.prefix}-${local.suffix}"
  kubernetes_version  = null # latest stable
  tags                = local.tags

  default_node_pool {
    name                = "system"
    node_count          = var.aks_node_count
    vm_size             = var.aks_vm_size
    os_disk_size_gb     = 128
    temporary_name_for_rotation = "tmppool"
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  }

  automatic_upgrade_channel = "patch"

  lifecycle {
    ignore_changes = [kubernetes_version]
  }
}

# --- AKS Diagnostic Settings ---
resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                       = "aks-diagnostics"
  target_resource_id         = azurerm_kubernetes_cluster.aks.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  enabled_log {
    category = "kube-apiserver"
  }

  enabled_log {
    category = "kube-audit"
  }

  enabled_log {
    category = "kube-audit-admin"
  }

  enabled_log {
    category = "cluster-autoscaler"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

# --- ACR Pull role for AKS kubelet ---
resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id                     = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.acr.id
  skip_service_principal_aad_check = true
}
