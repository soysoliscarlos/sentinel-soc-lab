variable "enable_ansible" {
  description = "Prepara SSH Windows y ejecuta Ansible desde Terraform en Windows con WSL Ubuntu. Requiere autorizacion de cambios y reinicios."
  type        = bool
  default     = false
  nullable    = false

  validation {
    condition     = !var.enable_ansible || (var.create_linux_vm && var.create_windows_vm)
    error_message = "enable_ansible requiere create_linux_vm = true y create_windows_vm = true. Desactiva Ansible para desplegar una sola VM o ninguna."
  }
}

locals {
  ansible_files = [
    "site.yml", "run.py", "Invoke-Ansible.ps1",
    "requirements.txt", "requirements.yml", "bootstrap-windows.ps1.tftpl",
    "linux-logging.yml", "files/Configure-ServiceLogging.ps1",
    "files/30-soc-apache.conf",
  ]
  ansible_config = var.create_linux_vm && var.create_windows_vm ? {
    subscription_id = var.subscription_id
    resource_group  = azurerm_resource_group.lab.name
    linux_vm        = azurerm_linux_virtual_machine.linux[0].name
    windows_vm      = azurerm_windows_virtual_machine.windows[0].name
    linux_ip        = azurerm_public_ip.vm["linux"].ip_address
    windows_ip      = azurerm_public_ip.vm["windows"].ip_address
    admin_username  = local.admin_username
    domain_name     = var.ad_domain_name
    domain_netbios  = var.ad_domain_netbios
  } : null
  windows_configuration_script = var.enable_ansible && var.create_windows_vm ? join("\n", [
    file("${path.module}/scripts/Configure-WindowsAudit.ps1"),
    templatefile("${path.module}/Ansible/bootstrap-windows.ps1.tftpl", {
      public_key = trimspace(tls_private_key.linux[0].public_key_openssh)
      admin_cidr = var.admin_source_cidr
    }),
  ]) : ""
  # La compresion evita superar los 8191 caracteres de cmd.exe en Custom Script.
  windows_configuration_loader = <<-POWERSHELL
    $ErrorActionPreference = 'Stop'
    $bytes = [Convert]::FromBase64String('${base64gzip(local.windows_configuration_script)}')
    $stream = [IO.MemoryStream]::new($bytes)
    $gzip = [IO.Compression.GzipStream]::new($stream, [IO.Compression.CompressionMode]::Decompress)
    $reader = [IO.StreamReader]::new($gzip)
    & ([scriptblock]::Create($reader.ReadToEnd()))
    $reader.Dispose()
  POWERSHELL
}

resource "random_password" "dsrm" {
  count = var.enable_ansible && var.create_linux_vm && var.create_windows_vm ? 1 : 0

  length           = 32
  min_upper        = 4
  min_lower        = 4
  min_numeric      = 4
  min_special      = 4
  override_special = "!#$%&*()-_=+?"
}

resource "azurerm_key_vault_secret" "dsrm" {
  count = var.enable_ansible && var.create_linux_vm && var.create_windows_vm ? 1 : 0

  name         = "windows-dsrm-password"
  value        = random_password.dsrm[0].result
  key_vault_id = azurerm_key_vault.lab.id
  content_type = "text/plain; charset=utf-8"
  tags         = local.tags

  depends_on = [azurerm_role_assignment.key_vault_secrets]
}

resource "terraform_data" "ansible" {
  count = var.enable_ansible && var.create_linux_vm && var.create_windows_vm ? 1 : 0

  triggers_replace = [
    sha256(jsonencode(local.ansible_config)),
    sha256(join("", [for name in local.ansible_files : filesha256("${path.module}/Ansible/${name}")])),
    azurerm_linux_virtual_machine.linux[0].id,
    azurerm_windows_virtual_machine.windows[0].id,
    sha256(tls_private_key.linux[0].private_key_openssh),
    sha256(random_password.dsrm[0].result),
  ]

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command"]
    command     = "& $env:SOC_ANSIBLE_LAUNCHER"
    environment = {
      SOC_ANSIBLE_LAUNCHER    = abspath("${path.module}/Ansible/Invoke-Ansible.ps1")
      SOC_ANSIBLE_CONFIG      = jsonencode(local.ansible_config)
      SOC_ANSIBLE_PRIVATE_KEY = tls_private_key.linux[0].private_key_openssh
      SOC_DSRM_PASSWORD       = random_password.dsrm[0].result
    }
  }

  depends_on = [
    azurerm_virtual_machine_extension.windows_audit,
    azurerm_virtual_machine_extension.linux_monitor,
    azurerm_network_interface_security_group_association.vm,
    azurerm_key_vault_secret.dsrm,
  ]
}
