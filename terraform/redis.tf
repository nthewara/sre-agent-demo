# --- Azure Cache for Redis ---
resource "azurerm_redis_cache" "redis" {
  name                = "redis-${var.prefix}-${local.suffix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  capacity            = 0
  family              = "C"
  sku_name            = "Basic"
  minimum_tls_version = "1.2"
  tags                = local.tags

  redis_configuration {}
}

# --- Redis Diagnostic Settings ---
resource "azurerm_monitor_diagnostic_setting" "redis" {
  name                       = "redis-diagnostics"
  target_resource_id         = azurerm_redis_cache.redis.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
