variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
}

variable "kvid" {
  description = "Resource ID of the Key Vault containing secrets"
  type        = string
}

variable "prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "sreagent"
}

variable "location" {
  description = "Azure region for all resources"
  type        = string
  default     = "australiaeast"
}

variable "alert_email" {
  description = "Email address for alert notifications"
  type        = string
  default     = "sre-team@contoso.com"
}

variable "aks_node_count" {
  description = "Number of AKS nodes"
  type        = number
  default     = 3
}

variable "aks_vm_size" {
  description = "VM size for AKS nodes"
  type        = string
  default     = "Standard_D2s_v5"
}
