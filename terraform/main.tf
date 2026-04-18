# --- Random suffix & locals ---
resource "random_string" "suffix" {
  length  = 4
  special = false
  numeric = false
  upper   = false
}

locals {
  suffix = random_string.suffix.result
  tags = {
    project     = "sre-agent-demo"
    environment = "demo"
    managed_by  = "terraform"
  }
}

# --- Key Vault data sources ---
data "azurerm_key_vault" "kv" {
  name                = split("/", var.kvid)[8]
  resource_group_name = split("/", var.kvid)[4]
}

data "azurerm_key_vault_secret" "password" {
  name         = "password"
  key_vault_id = var.kvid
}

data "azurerm_key_vault_secret" "username" {
  name         = "username"
  key_vault_id = var.kvid
}

data "azurerm_key_vault_secret" "myip" {
  name         = "myip"
  key_vault_id = var.kvid
}

# --- Resource Group ---
resource "azurerm_resource_group" "rg" {
  name     = "rg-${var.prefix}-${local.suffix}"
  location = var.location
  tags     = local.tags
}

# --- Log Analytics Workspace ---
resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-${var.prefix}-${local.suffix}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

# --- Container Registry ---
resource "azurerm_container_registry" "acr" {
  name                = "acr${var.prefix}${local.suffix}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = local.tags
}
