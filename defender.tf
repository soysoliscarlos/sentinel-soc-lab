variable "enable_defender_for_servers" {
  description = "Enables Microsoft Defender for Servers (Plan 1 by default) and onboards VMs to Microsoft Defender for Endpoint (Device Inventory)."
  type        = bool
  default     = false
  nullable    = false
}

variable "defender_servers_subplan" {
  description = "Microsoft Defender for Servers subplan (P1 or P2). Plan 1 includes full Defender for Endpoint licensing."
  type        = string
  default     = "P1"
  nullable    = false

  validation {
    condition     = contains(["P1", "P2"], var.defender_servers_subplan)
    error_message = "Defender for Servers subplan must be 'P1' or 'P2'."
  }
}

# 1. Enable Defender for Servers at the subscription level (Plan 1 provides MDE licensing for VMs)
resource "azurerm_security_center_subscription_pricing" "servers" {
  count         = var.enable_defender_for_servers ? 1 : 0
  tier          = "Standard"
  resource_type = "VirtualMachines"
  subplan       = var.defender_servers_subplan
}

# 2. Bidirectional integration with Microsoft Defender for Endpoint (WDATP)
resource "azurerm_security_center_setting" "wdatp" {
  count        = var.enable_defender_for_servers ? 1 : 0
  setting_name = "WDATP"
  enabled      = true
}

# 3. MDE extension on the Windows VM for immediate onboarding into Device Inventory
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

# 4. MDE extension on the Linux VM for immediate onboarding into Device Inventory
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
