variable "enable_defender_for_servers" {
  description = "Habilita Microsoft Defender for Servers (Plan 1) y el onboarding de las VMs a Microsoft Defender for Endpoint (Device Inventory)."
  type        = bool
  default     = false
  nullable    = false
}

variable "defender_servers_subplan" {
  description = "Subplan de Microsoft Defender for Servers (P1 o P2). El Plan 1 incluye licenciamiento completo de Defender for Endpoint."
  type        = string
  default     = "P1"
  nullable    = false

  validation {
    condition     = contains(["P1", "P2"], var.defender_servers_subplan)
    error_message = "El subplan de Defender for Servers debe ser 'P1' o 'P2'."
  }
}

# 1. Habilitar Defender for Servers a nivel de suscripcion (Plan 1 provee licenciamiento MDE para VMs)
resource "azurerm_security_center_subscription_pricing" "servers" {
  count         = var.enable_defender_for_servers ? 1 : 0
  tier          = "Standard"
  resource_type = "VirtualMachines"
  subplan       = var.defender_servers_subplan
}

# 2. Integracion bidireccional con Microsoft Defender for Endpoint (WDATP)
resource "azurerm_security_center_setting" "wdatp" {
  count        = var.enable_defender_for_servers ? 1 : 0
  setting_name = "WDATP"
  enabled      = true
}

# 3. Extension MDE en la VM Windows para onboarding inmediato en Device Inventory
resource "azurerm_virtual_machine_extension" "windows_mde" {
  count = var.enable_defender_for_servers && var.create_windows_vm ? 1 : 0

  name                       = "MDE.Windows"
  virtual_machine_id         = azurerm_windows_virtual_machine.windows[0].id
  publisher                  = "Microsoft.Azure.AzureDefenderForServers"
  type                       = "MDE.Windows"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true
  tags                       = local.tags

  settings = jsonencode({})

  lifecycle {
    ignore_changes = [settings]
  }

  depends_on = [
    azurerm_security_center_subscription_pricing.servers,
    azurerm_security_center_setting.wdatp,
    azurerm_virtual_machine_extension.windows_monitor
  ]
}

# 4. Extension MDE en la VM Linux para onboarding inmediato en Device Inventory
resource "azurerm_virtual_machine_extension" "linux_mde" {
  count = var.enable_defender_for_servers && var.create_linux_vm ? 1 : 0

  name                       = "MDE.Linux"
  virtual_machine_id         = azurerm_linux_virtual_machine.linux[0].id
  publisher                  = "Microsoft.Azure.AzureDefenderForServers"
  type                       = "MDE.Linux"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true
  tags                       = local.tags

  settings = jsonencode({})

  lifecycle {
    ignore_changes = [settings]
  }

  depends_on = [
    azurerm_security_center_subscription_pricing.servers,
    azurerm_security_center_setting.wdatp,
    azurerm_virtual_machine_extension.linux_monitor
  ]
}
