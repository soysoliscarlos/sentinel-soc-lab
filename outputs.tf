output "aks_cluster_name" {
  description = "AKS cluster name used to fetch Entra ID user credentials; exports neither kubeconfig nor secrets."
  value       = one(azurerm_kubernetes_cluster.lab[*].name)
}

output "app_service_url" {
  description = "Public HTTPS endpoint for App Service; deployed without Application Gateway or WAF."
  value       = var.create_app_service ? "https://${azurerm_linux_web_app.web[0].default_hostname}" : null
}

output "key_vault_name" {
  description = "Key Vault name configured with Private Endpoint and restricted public network firewall."
  value       = azurerm_key_vault.lab.name
}

output "key_vault_private_ip" {
  description = "Private IP address of the Key Vault Private Endpoint inside the VNet."
  value       = azurerm_private_endpoint.key_vault.private_service_connection[0].private_ip_address
}

output "linux_ssh_private_key" {
  description = "Generated RSA private key for socadmin; sensitive and persisted in Terraform state. Never store in OneDrive."
  value       = var.create_linux_vm ? tls_private_key.linux[0].private_key_openssh : null
  sensitive   = true
}

output "linux_ssh_public_key_secret_id" {
  description = "Versioned Key Vault secret ID containing only the Linux SSH public key."
  value       = one(azurerm_key_vault_secret.linux_ssh_public_key[*].id)
}

output "linux_public_ip" {
  description = "Static public IP of the Ubuntu VM; SSH as socadmin allowed only from admin_source_cidr."
  value       = var.create_linux_vm ? azurerm_public_ip.vm["linux"].ip_address : null
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the shared Log Analytics workspace used by all telemetry sources."
  value       = azurerm_log_analytics_workspace.soc.id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics workspace for querying telemetry in Microsoft Sentinel."
  value       = azurerm_log_analytics_workspace.soc.name
}

output "resource_group_name" {
  description = "Lab resource group name; AKS also creates its managed MC_ resource group."
  value       = azurerm_resource_group.lab.name
}

output "sentinel_onboarding_id" {
  description = "Resource ID of the Microsoft Sentinel onboarding resource on the workspace."
  value       = azurerm_sentinel_log_analytics_workspace_onboarding.soc.id
}

output "windows_public_ip" {
  description = "Static public IP of Windows Server; RDP as socadmin allowed only from admin_source_cidr."
  value       = var.create_windows_vm ? azurerm_public_ip.vm["windows"].ip_address : null
}

output "windows_admin_password_secret_id" {
  description = "Versioned Key Vault secret ID storing the generated socadmin password; never exposes its cleartext value."
  value       = one(azurerm_key_vault_secret.windows_admin_password[*].id)
}
