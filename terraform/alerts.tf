# --- Action Group ---
resource "azurerm_monitor_action_group" "sre" {
  name                = "ag-sre-alerts-${local.suffix}"
  resource_group_name = azurerm_resource_group.rg.name
  short_name          = "SREAlerts"
  tags                = local.tags

  email_receiver {
    name                    = "SRE Team"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }
}

# =============================================
# Metric Alerts (AKS cluster scoped)
# =============================================

resource "azurerm_monitor_metric_alert" "high_cpu" {
  name                = "alert-aks-high-cpu-${local.suffix}"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_kubernetes_cluster.aks.id]
  description         = "Alert when AKS node CPU usage exceeds 80%"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.tags

  criteria {
    metric_namespace = "Insights.Container/nodes"
    metric_name      = "node_cpu_usage_percentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
    skip_metric_validation = true
  }

  action {
    action_group_id = azurerm_monitor_action_group.sre.id
  }
}

resource "azurerm_monitor_metric_alert" "high_memory" {
  name                = "alert-aks-high-memory-${local.suffix}"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_kubernetes_cluster.aks.id]
  description         = "Alert when AKS node memory usage exceeds 80%"
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.tags

  criteria {
    metric_namespace = "Insights.Container/nodes"
    metric_name      = "node_memory_working_set_percentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
    skip_metric_validation = true
  }

  action {
    action_group_id = azurerm_monitor_action_group.sre.id
  }
}

resource "azurerm_monitor_metric_alert" "pod_restarts" {
  name                = "alert-aks-pod-restarts-${local.suffix}"
  resource_group_name = azurerm_resource_group.rg.name
  scopes              = [azurerm_kubernetes_cluster.aks.id]
  description         = "Alert when pods restart frequently"
  severity            = 3
  frequency           = "PT5M"
  window_size         = "PT15M"
  tags                = local.tags

  criteria {
    metric_namespace = "Insights.Container/pods"
    metric_name      = "restarting_container_count"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 3
    skip_metric_validation = true
  }

  action {
    action_group_id = azurerm_monitor_action_group.sre.id
  }
}

# =============================================
# Log-based Alerts (LAW scoped)
# =============================================

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "container_errors" {
  name                = "alert-container-errors-${local.suffix}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  display_name        = "Container Error Logs Alert"
  description         = "Alert when container logs contain errors"
  severity            = 2
  enabled             = true
  evaluation_frequency = "PT5M"
  scopes              = [azurerm_log_analytics_workspace.law.id]
  window_duration     = "PT15M"
  tags                = local.tags

  criteria {
    query = <<-QUERY
      ContainerLogV2
      | where LogLevel == "error" or LogMessage contains "error" or LogMessage contains "exception"
      | summarize ErrorCount = count() by ContainerName, PodName, bin(TimeGenerated, 5m)
    QUERY
    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 10
    failing_periods {
      number_of_evaluation_periods = 1
      minimum_failing_periods_to_trigger_alert = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.sre.id]
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "oom_killed" {
  name                = "alert-oom-killed-${local.suffix}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  display_name        = "OOMKilled Container Alert"
  description         = "Alert when containers are killed due to Out of Memory"
  severity            = 1
  enabled             = true
  evaluation_frequency = "PT5M"
  scopes              = [azurerm_log_analytics_workspace.law.id]
  window_duration     = "PT15M"
  tags                = local.tags

  criteria {
    query = <<-QUERY
      KubeEvents
      | where Reason == "OOMKilled"
      | summarize OOMCount = count() by Name, Namespace, bin(TimeGenerated, 5m)
    QUERY
    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 0
    failing_periods {
      number_of_evaluation_periods = 1
      minimum_failing_periods_to_trigger_alert = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.sre.id]
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "job_failures" {
  name                = "alert-job-failures-${local.suffix}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  display_name        = "Kubernetes Job Failure Alert"
  description         = "Alert when Kubernetes jobs fail"
  severity            = 2
  enabled             = true
  evaluation_frequency = "PT5M"
  scopes              = [azurerm_log_analytics_workspace.law.id]
  window_duration     = "PT30M"
  tags                = local.tags

  criteria {
    query = <<-QUERY
      KubeEvents
      | where Reason == "BackoffLimitExceeded" or Reason == "Failed"
      | where ObjectKind == "Job"
      | summarize FailureCount = count() by Name, Namespace, bin(TimeGenerated, 5m)
    QUERY
    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 0
    failing_periods {
      number_of_evaluation_periods = 1
      minimum_failing_periods_to_trigger_alert = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.sre.id]
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "pods_not_ready" {
  name                = "alert-pods-not-ready-${local.suffix}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  display_name        = "Pods Not Ready Alert"
  description         = "Alert when pods fail readiness probes or are not ready"
  severity            = 1
  enabled             = true
  evaluation_frequency = "PT5M"
  scopes              = [azurerm_log_analytics_workspace.law.id]
  window_duration     = "PT15M"
  tags                = local.tags

  criteria {
    query = <<-QUERY
      KubePodInventory
      | where Namespace == "aks-journal-app"
      | where PodStatus != "Running" or ContainerStatusReason != ""
      | summarize NotReadyCount = dcount(PodUid) by Namespace, bin(TimeGenerated, 5m)
    QUERY
    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 0
    failing_periods {
      number_of_evaluation_periods = 1
      minimum_failing_periods_to_trigger_alert = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.sre.id]
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "redis_connection_errors" {
  name                = "alert-redis-conn-errors-${local.suffix}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  display_name        = "Redis Connection Error Alert"
  description         = "Alert when Redis connection failures are detected in logs"
  severity            = 1
  enabled             = true
  evaluation_frequency = "PT5M"
  scopes              = [azurerm_log_analytics_workspace.law.id]
  window_duration     = "PT15M"
  tags                = local.tags

  criteria {
    query = <<-QUERY
      ContainerLogV2
      | where LogMessage has_any ("Redis", "WRONGPASS", "NOAUTH", "connection refused", "ECONNREFUSED")
      | where LogMessage has_any ("error", "failed", "Error", "Failed")
      | summarize ErrorCount = count() by ContainerName, bin(TimeGenerated, 5m)
    QUERY
    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 0
    failing_periods {
      number_of_evaluation_periods = 1
      minimum_failing_periods_to_trigger_alert = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.sre.id]
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "probe_failures" {
  name                = "alert-probe-failures-${local.suffix}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  display_name        = "Probe Failure Alert"
  description         = "Alert when readiness/liveness probes fail in aks-journal-app namespace"
  severity            = 2
  enabled             = true
  evaluation_frequency = "PT5M"
  scopes              = [azurerm_log_analytics_workspace.law.id]
  window_duration     = "PT15M"
  tags                = local.tags

  criteria {
    query = <<-QUERY
      KubeEvents
      | where TimeGenerated >= ago(15m)
      | where Namespace == "aks-journal-app"
      | where Reason in ("Unhealthy", "UnhealthyReadinessProbe", "UnhealthyLivenessProbe") or Message contains "probe failed"
      | summarize Failures = count() by Name, Namespace, bin(TimeGenerated, 5m)
    QUERY
    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 0
    failing_periods {
      number_of_evaluation_periods = 1
      minimum_failing_periods_to_trigger_alert = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.sre.id]
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "ingress_timeouts" {
  name                = "alert-ingress-timeouts-${local.suffix}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  display_name        = "Ingress Timeout Alert"
  description         = "Alert when ingress shows 5xx/timeout errors"
  severity            = 2
  enabled             = true
  evaluation_frequency = "PT5M"
  scopes              = [azurerm_log_analytics_workspace.law.id]
  window_duration     = "PT15M"
  tags                = local.tags

  criteria {
    query = <<-QUERY
      ContainerLogV2
      | where TimeGenerated >= ago(15m)
      | where ContainerName contains "ingress" or PodName contains "ingress"
      | where LogMessage contains "upstream timed out" or LogMessage contains "504" or LogMessage contains "timeout"
      | summarize Events = count() by bin(TimeGenerated, 5m)
    QUERY
    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 5
    failing_periods {
      number_of_evaluation_periods = 1
      minimum_failing_periods_to_trigger_alert = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.sre.id]
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "backoff_events" {
  name                = "alert-backoff-events-${local.suffix}"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  display_name        = "Container BackOff Alert"
  description         = "Alert when containers enter BackOff state (crash loop)"
  severity            = 1
  enabled             = true
  evaluation_frequency = "PT5M"
  scopes              = [azurerm_log_analytics_workspace.law.id]
  window_duration     = "PT15M"
  tags                = local.tags

  criteria {
    query = <<-QUERY
      KubeEvents
      | where TimeGenerated >= ago(15m)
      | where Namespace == "aks-journal-app"
      | where Reason == "BackOff"
      | summarize BackOffCount = count() by Name, Namespace, bin(TimeGenerated, 5m)
    QUERY
    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 0
    failing_periods {
      number_of_evaluation_periods = 1
      minimum_failing_periods_to_trigger_alert = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.sre.id]
  }
}
