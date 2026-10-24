resource "random_password" "windows_admin" {
  count = var.create_windows_vm ? 1 : 0

  length           = 32
  upper            = true
  lower            = true
  numeric          = true
  special          = true
  min_upper        = 4
  min_lower        = 4
  min_numeric      = 4
  min_special      = 4
  override_special = "!#$%&*()-_=+?"
}

resource "azurerm_linux_virtual_machine" "linux" {
  count = var.create_linux_vm ? 1 : 0

  name                            = "${var.name_prefix}-linux"
  computer_name                   = "${var.name_prefix}-linux"
  location                        = azurerm_resource_group.lab.location
  resource_group_name             = azurerm_resource_group.lab.name
  size                            = var.linux_vm_size
  admin_username                  = local.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.vm["linux"].id]
  provision_vm_agent              = true
  tags                            = local.tags

  custom_data = base64encode("#cloud-config\n${yamlencode({
    packages = ["rsyslog"]
    runcmd   = [["systemctl", "enable", "--now", "rsyslog"]]
  })}")

  admin_ssh_key {
    username   = local.admin_username
    public_key = azurerm_ssh_public_key.linux[0].public_key
  }

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.linux_os_disk_sku
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = var.linux_image_sku
    version   = "latest"
  }

  depends_on = [azurerm_network_interface_security_group_association.vm]
}

resource "azurerm_windows_virtual_machine" "windows" {
  count = var.create_windows_vm ? 1 : 0

  name                      = "${var.name_prefix}-windows"
  computer_name             = "soc-win"
  location                  = azurerm_resource_group.lab.location
  resource_group_name       = azurerm_resource_group.lab.name
  size                      = var.windows_vm_size
  admin_username            = local.admin_username
  admin_password            = random_password.windows_admin[0].result
  network_interface_ids     = [azurerm_network_interface.vm["windows"].id]
  provision_vm_agent        = true
  automatic_updates_enabled = true
  tags                      = local.tags

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    caching              = var.enable_ansible ? "None" : "ReadWrite"
    storage_account_type = var.windows_os_disk_sku
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = var.windows_image_sku
    version   = "latest"
  }

  depends_on = [azurerm_network_interface_security_group_association.vm]
}

resource "azurerm_virtual_machine_extension" "linux_monitor" {
  count = var.create_linux_vm ? 1 : 0

  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = azurerm_linux_virtual_machine.linux[0].id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true
  tags                       = local.tags
}

resource "azurerm_virtual_machine_extension" "windows_monitor" {
  count = var.create_windows_vm ? 1 : 0

  name                       = "AzureMonitorWindowsAgent"
  virtual_machine_id         = azurerm_windows_virtual_machine.windows[0].id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorWindowsAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true
  tags                       = local.tags
}

resource "azurerm_virtual_machine_extension" "windows_audit" {
  count = var.create_windows_vm ? 1 : 0

  name                       = "ConfigureWindowsAudit"
  virtual_machine_id         = azurerm_windows_virtual_machine.windows[0].id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true
  tags                       = local.tags

  settings = jsonencode({
    commandToExecute = "powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ${textencodebase64(var.enable_ansible ? local.windows_configuration_loader : file("${path.module}/scripts/Configure-WindowsAudit.ps1"), "UTF-16LE")}"
  })

  depends_on = [azurerm_virtual_machine_extension.windows_monitor]
}
