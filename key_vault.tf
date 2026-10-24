resource "tls_private_key" "linux" {
  count = var.create_linux_vm || (var.enable_ansible && var.create_windows_vm) ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_ssh_public_key" "linux" {
  count = var.create_linux_vm ? 1 : 0

  name                = "${var.name_prefix}-linux-ssh"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  public_key          = trimspace(tls_private_key.linux[0].public_key_openssh)
  tags                = local.tags
}

resource "azurerm_key_vault" "lab" {
  name                          = "${var.name_prefix}-${var.key_vault_name_suffix}"
  location                      = azurerm_resource_group.lab.location
  resource_group_name           = azurerm_resource_group.lab.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = var.key_vault_sku
  rbac_authorization_enabled    = true
  public_network_access_enabled = true
  soft_delete_retention_days    = 7
  # Debe permanecer deshabilitado para que terraform destroy pueda purgar el vault.
  purge_protection_enabled = false
  tags                     = local.tags

  network_acls {
    bypass         = "None"
    default_action = "Deny"
    ip_rules       = [var.admin_source_cidr]
  }
}

resource "azurerm_role_assignment" "key_vault_secrets" {
  scope                = azurerm_key_vault.lab.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_subnet" "private_endpoint" {
  name                 = "snet-private-endpoints"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = ["10.20.3.0/24"]
}

resource "azurerm_private_dns_zone" "key_vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "key_vault" {
  name                 = "${var.name_prefix}-kv-dns-link"
  private_dns_zone_id  = azurerm_private_dns_zone.key_vault.id
  virtual_network_id   = azurerm_virtual_network.lab.id
  registration_enabled = false
  tags                 = local.tags
}

resource "azurerm_private_endpoint" "key_vault" {
  name                = "${var.name_prefix}-kv-pe"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  subnet_id           = azurerm_subnet.private_endpoint.id
  tags                = local.tags

  private_service_connection {
    name                           = "${var.name_prefix}-kv-connection"
    private_connection_resource_id = azurerm_key_vault.lab.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "key-vault"
    private_dns_zone_ids = [azurerm_private_dns_zone.key_vault.id]
  }
}

resource "azurerm_key_vault_secret" "linux_ssh_public_key" {
  count = var.create_linux_vm ? 1 : 0

  name         = "linux-ssh-public-key"
  value        = azurerm_ssh_public_key.linux[0].public_key
  key_vault_id = azurerm_key_vault.lab.id
  content_type = "text/plain; charset=utf-8"
  tags         = local.tags

  depends_on = [azurerm_role_assignment.key_vault_secrets]
}

resource "azurerm_key_vault_secret" "windows_admin_password" {
  count = var.create_windows_vm ? 1 : 0

  name         = "windows-admin-password"
  value        = random_password.windows_admin[0].result
  key_vault_id = azurerm_key_vault.lab.id
  content_type = "text/plain; charset=utf-8"
  tags         = local.tags

  depends_on = [azurerm_role_assignment.key_vault_secrets]
}

resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  name                           = "soc-workspace"
  target_resource_id             = azurerm_key_vault.lab.id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.soc.id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category = "AuditEvent"
  }
}
