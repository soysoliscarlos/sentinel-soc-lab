locals {
  windows_security_event_ids = concat(
    [4624, 4625, 4634, 4648, 4672, 4688, 4720, 4726, 4732, 4733, 4740, 1102],
    var.enable_ansible ? [
      4719, 4722, 4723, 4724, 4725, 4727, 4728, 4729, 4730, 4731,
      4734, 4735, 4737, 4738, 4739, 4741, 4742, 4743,
      4754, 4755, 4756, 4757, 4758, 4767, 4768, 4769, 4770, 4771,
      4772, 4776, 4777, 4781, 5136, 5137, 5138, 5139, 5141,
    ] : []
  )
}

resource "azurerm_monitor_data_collection_rule" "linux" {
  count = var.create_linux_vm ? 1 : 0

  name                = "${var.name_prefix}-linux-dcr"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  kind                = "Linux"
  tags                = local.tags

  destinations {
    log_analytics {
      name                  = "soc"
      workspace_resource_id = azurerm_log_analytics_workspace.soc.id
    }
  }

  data_sources {
    syslog {
      name           = "linux-syslog"
      facility_names = concat(["auth", "authpriv", "daemon", "syslog", "kern"], var.enable_ansible ? ["local5", "local6"] : [])
      log_levels     = ["Info", "Notice", "Warning", "Error", "Critical", "Alert", "Emergency"]
      streams        = ["Microsoft-Syslog"]
    }
  }

  data_flow {
    streams      = ["Microsoft-Syslog"]
    destinations = ["soc"]
  }

  depends_on = [terraform_data.ansible]
}

resource "azurerm_monitor_data_collection_rule" "windows" {
  count = var.create_windows_vm ? 1 : 0

  name                = "${var.name_prefix}-windows-dcr"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  kind                = "Windows"
  tags                = local.tags

  destinations {
    log_analytics {
      name                  = "soc"
      workspace_resource_id = azurerm_log_analytics_workspace.soc.id
    }
  }

  data_sources {
    windows_event_log {
      name    = "security"
      streams = ["Microsoft-SecurityEvent"]
      x_path_queries = [
        for ids in chunklist(local.windows_security_event_ids, 20) :
        "Security!*[System[(${join(" or ", [for id in ids : "EventID=${id}"])})]]"
      ]
    }

    windows_event_log {
      name           = "system-application"
      streams        = ["Microsoft-Event"]
      x_path_queries = ["System!*[System[(Level=1 or Level=2 or Level=3)]]", "Application!*[System[(Level=1 or Level=2 or Level=3)]]"]
    }

    dynamic "windows_event_log" {
      for_each = var.enable_ansible ? [true] : []
      content {
        name    = "adds-services"
        streams = ["Microsoft-Event"]
        x_path_queries = [
          "Directory Service!*[System[(Level=1 or Level=2 or Level=3)]]",
          "DNS Server!*[System[(Level=1 or Level=2 or Level=3)]]",
          "DFS Replication!*[System[(Level=1 or Level=2 or Level=3)]]",
        ]
      }
    }

    dynamic "iis_log" {
      for_each = var.enable_ansible ? [true] : []
      content {
        name            = "iis-w3c"
        streams         = ["Microsoft-W3CIISLog"]
        log_directories = ["C:\\inetpub\\logs\\LogFiles\\W3SVC1"]
      }
    }
  }

  data_flow {
    streams      = concat(["Microsoft-SecurityEvent", "Microsoft-Event"], var.enable_ansible ? ["Microsoft-W3CIISLog"] : [])
    destinations = ["soc"]
  }

  depends_on = [azurerm_sentinel_log_analytics_workspace_onboarding.soc, terraform_data.ansible]
}

resource "azurerm_monitor_data_collection_rule_association" "linux" {
  count = var.create_linux_vm ? 1 : 0

  name                    = "linux-monitoring"
  target_resource_id      = azurerm_linux_virtual_machine.linux[0].id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.linux[0].id

  depends_on = [azurerm_virtual_machine_extension.linux_monitor]
}

resource "azurerm_monitor_data_collection_rule_association" "windows" {
  count = var.create_windows_vm ? 1 : 0

  name                    = "windows-monitoring"
  target_resource_id      = azurerm_windows_virtual_machine.windows[0].id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.windows[0].id

  depends_on = [azurerm_virtual_machine_extension.windows_monitor]
}

resource "azurerm_monitor_data_collection_rule" "aks" {
  count = var.create_aks ? 1 : 0

  name                = "MSCI-${var.name_prefix}-aks"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  kind                = "Linux"
  tags                = local.tags

  destinations {
    log_analytics {
      name                  = "soc"
      workspace_resource_id = azurerm_log_analytics_workspace.soc.id
    }
  }

  data_sources {
    extension {
      name           = "ContainerInsightsExtension"
      extension_name = "ContainerInsights"
      streams        = local.container_streams
      extension_json = jsonencode({
        dataCollectionSettings = {
          interval               = "5m"
          namespaceFilteringMode = "Off"
          enableContainerLogV2   = true
        }
      })
    }
  }

  data_flow {
    streams      = local.container_streams
    destinations = ["soc"]
  }
}

resource "azurerm_monitor_data_collection_rule_association" "aks" {
  count = var.create_aks ? 1 : 0

  name                    = "ContainerInsightsExtension"
  target_resource_id      = azurerm_kubernetes_cluster.lab[0].id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.aks[0].id

}

resource "azurerm_monitor_diagnostic_setting" "web" {
  count = var.create_app_service ? 1 : 0

  name                           = "soc-workspace"
  target_resource_id             = azurerm_linux_web_app.web[0].id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.soc.id
  log_analytics_destination_type = "Dedicated"

  dynamic "enabled_log" {
    for_each = toset(["AppServiceHTTPLogs", "AppServiceConsoleLogs", "AppServiceAuditLogs", "AppServiceIPSecAuditLogs", "AppServicePlatformLogs"])
    content {
      category = enabled_log.value
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "aks" {
  count = var.create_aks ? 1 : 0

  name                           = "soc-workspace"
  target_resource_id             = azurerm_kubernetes_cluster.lab[0].id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.soc.id
  log_analytics_destination_type = "Dedicated"

  dynamic "enabled_log" {
    for_each = toset(["kube-audit-admin", "kube-apiserver", "kube-controller-manager", "kube-scheduler", "cluster-autoscaler", "guard"])
    content {
      category = enabled_log.value
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "activity" {
  name                       = "${var.name_prefix}-activity"
  target_resource_id         = "/subscriptions/${var.subscription_id}"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.soc.id

  dynamic "enabled_log" {
    for_each = toset(["Administrative", "Security", "ServiceHealth", "Alert", "Recommendation", "Policy", "Autoscale", "ResourceHealth"])
    content {
      category = enabled_log.value
    }
  }

  depends_on = [azurerm_sentinel_log_analytics_workspace_onboarding.soc]
}
