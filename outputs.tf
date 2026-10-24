output "aks_cluster_name" {
  description = "Nombre AKS para obtener credenciales de usuario Entra ID; no exporta kubeconfig ni secretos."
  value       = one(azurerm_kubernetes_cluster.lab[*].name)
}

output "app_service_url" {
  description = "Endpoint HTTPS publico de App Service; sin Application Gateway ni WAF."
  value       = var.create_app_service ? "https://${azurerm_linux_web_app.web[0].default_hostname}" : null
}

output "key_vault_name" {
  description = "Nombre del Key Vault con acceso privado y endpoint publico restringido."
  value       = azurerm_key_vault.lab.name
}

output "key_vault_private_ip" {
  description = "IP privada del Private Endpoint de Key Vault en la VNet."
  value       = azurerm_private_endpoint.key_vault.private_service_connection[0].private_ip_address
}

output "linux_ssh_private_key" {
  description = "Clave privada RSA para socadmin; sensible, persistida en el estado. No guardarla en OneDrive."
  value       = var.create_linux_vm ? tls_private_key.linux[0].private_key_openssh : null
  sensitive   = true
}

output "linux_ssh_public_key_secret_id" {
  description = "ID versionado del secreto de Key Vault que contiene solo la clave publica Linux."
  value       = one(azurerm_key_vault_secret.linux_ssh_public_key[*].id)
}

output "linux_public_ip" {
  description = "IP publica estatica de Ubuntu; SSH como socadmin solo desde admin_source_cidr."
  value       = var.create_linux_vm ? azurerm_public_ip.vm["linux"].ip_address : null
}

output "log_analytics_workspace_id" {
  description = "Resource ID del workspace compartido por todos los origenes."
  value       = azurerm_log_analytics_workspace.soc.id
}

output "log_analytics_workspace_name" {
  description = "Nombre del workspace para consultar telemetria en Sentinel."
  value       = azurerm_log_analytics_workspace.soc.name
}

output "resource_group_name" {
  description = "Grupo de recursos del laboratorio; AKS tambien crea su grupo administrado MC_."
  value       = azurerm_resource_group.lab.name
}

output "sentinel_onboarding_id" {
  description = "Resource ID de la habilitacion de Microsoft Sentinel sobre el workspace."
  value       = azurerm_sentinel_log_analytics_workspace_onboarding.soc.id
}

output "windows_public_ip" {
  description = "IP publica estatica de Windows Server; RDP como socadmin solo desde admin_source_cidr."
  value       = var.create_windows_vm ? azurerm_public_ip.vm["windows"].ip_address : null
}

output "windows_admin_password_secret_id" {
  description = "ID versionado del secreto con la contrasena generada de socadmin; no expone su valor."
  value       = one(azurerm_key_vault_secret.windows_admin_password[*].id)
}
