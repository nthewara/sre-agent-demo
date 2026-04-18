output "resource_group_name" {
  value = azurerm_resource_group.rg.name
}

output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.aks.name
}

output "acr_login_server" {
  value = azurerm_container_registry.acr.login_server
}

output "acr_name" {
  value = azurerm_container_registry.acr.name
}

output "redis_hostname" {
  value = azurerm_redis_cache.redis.hostname
}

output "redis_port" {
  value = azurerm_redis_cache.redis.ssl_port
}

output "redis_primary_key" {
  value     = azurerm_redis_cache.redis.primary_access_key
  sensitive = true
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.law.id
}

output "log_analytics_workspace_name" {
  value = azurerm_log_analytics_workspace.law.name
}
