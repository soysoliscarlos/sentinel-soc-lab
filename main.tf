data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "lab" {
  name     = "${var.name_prefix}-rg"
  location = var.location
  tags     = local.tags
}

resource "azurerm_log_analytics_workspace" "soc" {
  name                           = "${var.name_prefix}-law"
  location                       = azurerm_resource_group.lab.location
  resource_group_name            = azurerm_resource_group.lab.name
  sku                            = var.log_workspace_sku
  retention_in_days              = var.log_retention_days
  daily_quota_gb                 = var.log_daily_quota_gb
  internet_ingestion_access_type = "Enabled"
  internet_query_access_type     = "Enabled"
  local_authentication_enabled   = false
  tags                           = local.tags
}

resource "azurerm_sentinel_log_analytics_workspace_onboarding" "soc" {
  workspace_id                 = azurerm_log_analytics_workspace.soc.id
  customer_managed_key_enabled = false
}

resource "azurerm_log_analytics_solution" "container_insights" {
  count = var.create_aks ? 1 : 0

  solution_name         = "ContainerInsights"
  location              = azurerm_resource_group.lab.location
  resource_group_name   = azurerm_resource_group.lab.name
  workspace_resource_id = azurerm_log_analytics_workspace.soc.id
  workspace_name        = azurerm_log_analytics_workspace.soc.name
  tags                  = local.tags

  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/ContainerInsights"
  }
}
