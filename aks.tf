resource "azurerm_user_assigned_identity" "aks" {
  count = var.create_aks ? 1 : 0

  name                = "${var.name_prefix}-aks-identity"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}

resource "azurerm_role_assignment" "aks_network" {
  count = var.create_aks ? 1 : 0

  scope                = azurerm_subnet.aks[0].id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks[0].principal_id
}

resource "azurerm_kubernetes_cluster" "lab" {
  count = var.create_aks ? 1 : 0

  name                              = "${var.name_prefix}-aks"
  location                          = azurerm_resource_group.lab.location
  resource_group_name               = azurerm_resource_group.lab.name
  dns_prefix                        = "${var.name_prefix}-aks"
  kubernetes_version                = var.kubernetes_version
  sku_tier                          = var.aks_sku_tier
  local_account_disabled            = true
  role_based_access_control_enabled = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true
  tags                              = local.tags

  node_provisioning_profile {
    mode = "Manual"
  }

  default_node_pool {
    name                        = "system"
    node_count                  = var.aks_node_count
    vm_size                     = var.aks_node_vm_size
    vnet_subnet_id              = azurerm_subnet.aks[0].id
    os_disk_size_gb             = 64
    os_disk_type                = "Managed"
    os_sku                      = var.aks_os_sku
    max_pods                    = 30
    temporary_name_for_rotation = "rotation"
    tags                        = local.tags

    upgrade_settings {
      drain_timeout_in_minutes      = 0
      max_surge                     = "10%"
      node_soak_duration_in_minutes = 0
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks[0].id]
  }

  azure_active_directory_role_based_access_control {
    tenant_id          = data.azurerm_client_config.current.tenant_id
    azure_rbac_enabled = true
  }

  api_server_access_profile {
    authorized_ip_ranges = [var.admin_source_cidr]
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_policy      = "azure"
    pod_cidr            = "10.244.0.0/16"
    service_cidr        = "10.30.0.0/16"
    dns_service_ip      = "10.30.0.10"
    outbound_type       = "loadBalancer"
    load_balancer_sku   = var.aks_load_balancer_sku
  }

  oms_agent {
    log_analytics_workspace_id      = azurerm_log_analytics_workspace.soc.id
    msi_auth_for_monitoring_enabled = true
  }

  depends_on = [
    azurerm_role_assignment.aks_network,
    azurerm_log_analytics_solution.container_insights,
  ]
}

resource "azurerm_role_assignment" "aks_admin" {
  count = var.create_aks ? 1 : 0

  scope                = azurerm_kubernetes_cluster.lab[0].id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}
