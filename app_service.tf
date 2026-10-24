resource "azurerm_service_plan" "web" {
  count = var.create_app_service ? 1 : 0

  name                = "${var.name_prefix}-plan"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  os_type             = "Linux"
  sku_name            = var.app_service_sku
  tags                = local.tags
}

resource "azurerm_linux_web_app" "web" {
  count = var.create_app_service ? 1 : 0

  name                                           = "${var.name_prefix}-web"
  location                                       = azurerm_resource_group.lab.location
  resource_group_name                            = azurerm_resource_group.lab.name
  service_plan_id                                = azurerm_service_plan.web[0].id
  https_only                                     = true
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false
  public_network_access_enabled                  = true
  tags                                           = local.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on           = true
    ftps_state          = "Disabled"
    minimum_tls_version = "1.2"
    http2_enabled       = true

    ip_restriction_default_action     = "Allow"
    scm_use_main_ip_restriction       = false
    scm_ip_restriction_default_action = "Allow"
  }

  logs {
    detailed_error_messages = true
    failed_request_tracing  = true

    http_logs {
      file_system {
        retention_in_days = 3
        retention_in_mb   = 25
      }
    }
  }
}
