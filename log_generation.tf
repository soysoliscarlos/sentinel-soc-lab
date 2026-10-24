variable "enable_log_generation" {
  description = "Ejecuta scripts/Invoke-SocLabLogGeneration.ps1 al final del apply para generar actividad benigna marcada en VM, App Service, Key Vault, ARM y AKS. Es una simulacion: requiere autorizacion."
  type        = bool
  default     = false
  nullable    = false
}

variable "log_generation_tests" {
  description = "Grupos de pruebas del script de generacion de logs."
  type        = list(string)
  default     = ["All"]
  nullable    = false

  validation {
    condition = length(var.log_generation_tests) > 0 && alltrue([
      for test in var.log_generation_tests :
      contains(["All", "Windows", "Linux", "WebServers", "AppService", "KeyVault", "Arm", "Aks"], test)
    ])
    error_message = "Usa All o una lista de Windows, Linux, WebServers, AppService, KeyVault, Arm y Aks."
  }
}

variable "log_generation_wait_minutes" {
  description = "Minutos maximos para esperar Heartbeat de las VM habilitadas y KubePodInventory de AKS si existe antes de generar actividad."
  type        = number
  default     = 30
  nullable    = false

  validation {
    condition     = var.log_generation_wait_minutes >= 1 && var.log_generation_wait_minutes <= 60
    error_message = "La espera de fuentes debe estar entre 1 y 60 minutos."
  }
}

variable "log_generation_initial_delay_seconds" {
  description = "Espera adicional para que los diagnostic settings recien creados empiecen a exportar."
  type        = number
  default     = 300
  nullable    = false

  validation {
    condition     = var.log_generation_initial_delay_seconds >= 0 && var.log_generation_initial_delay_seconds <= 1800
    error_message = "La espera inicial debe estar entre 0 y 1800 segundos."
  }
}

variable "log_generation_verify" {
  description = "Consulta el workspace hasta ver cada marcador; una ingesta pendiente solo se informa, no falla el apply."
  type        = bool
  default     = true
  nullable    = false
}

variable "log_generation_trigger" {
  description = "Valor libre; cambiarlo vuelve a ejecutar la generacion de logs en el siguiente apply."
  type        = string
  default     = "inicial"
  nullable    = false
}

resource "terraform_data" "log_generation" {
  count = var.enable_log_generation ? 1 : 0

  # Solo se reejecuta si cambia una fuente conectada, el script o el disparador manual.
  triggers_replace = [
    var.log_generation_trigger,
    join(",", var.log_generation_tests),
    filesha256("${path.module}/scripts/Invoke-SocLabLogGeneration.ps1"),
    one(azurerm_monitor_data_collection_rule_association.linux[*].id),
    one(azurerm_monitor_data_collection_rule_association.windows[*].id),
    one(azurerm_monitor_data_collection_rule_association.aks[*].id),
    one(azurerm_monitor_diagnostic_setting.web[*].id),
    one(azurerm_monitor_diagnostic_setting.aks[*].id),
    azurerm_monitor_diagnostic_setting.key_vault.id,
    azurerm_monitor_diagnostic_setting.activity.id,
  ]

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command"]
    command     = <<-POWERSHELL
      try {
        & $env:SOC_LOGGEN_SCRIPT -SubscriptionId $env:SOC_LOGGEN_SUBSCRIPTION -ResourceGroup $env:SOC_LOGGEN_RESOURCE_GROUP `
          -Test ($env:SOC_LOGGEN_TESTS -split ',') -WaitForSourcesMinutes ([int]$env:SOC_LOGGEN_WAIT_MINUTES) `
          -InitialDelaySeconds ([int]$env:SOC_LOGGEN_DELAY_SECONDS) -Verify:($env:SOC_LOGGEN_VERIFY -eq 'true')
        exit $LASTEXITCODE
      }
      catch {
        Write-Error $_
        exit 1
      }
    POWERSHELL
    environment = {
      SOC_LOGGEN_SCRIPT         = abspath("${path.module}/scripts/Invoke-SocLabLogGeneration.ps1")
      SOC_LOGGEN_SUBSCRIPTION   = var.subscription_id
      SOC_LOGGEN_RESOURCE_GROUP = azurerm_resource_group.lab.name
      SOC_LOGGEN_TESTS          = join(",", var.log_generation_tests)
      SOC_LOGGEN_WAIT_MINUTES   = tostring(var.log_generation_wait_minutes)
      SOC_LOGGEN_DELAY_SECONDS  = tostring(var.log_generation_initial_delay_seconds)
      SOC_LOGGEN_VERIFY         = tostring(var.log_generation_verify)
    }
  }

  # Ultimo paso del despliegue: recursos, auditoria Windows, Ansible, recoleccion y Sentinel ya existen.
  depends_on = [
    terraform_data.ansible,
    azurerm_virtual_machine_extension.linux_monitor,
    azurerm_virtual_machine_extension.windows_monitor,
    azurerm_virtual_machine_extension.windows_audit,
    azurerm_monitor_data_collection_rule_association.linux,
    azurerm_monitor_data_collection_rule_association.windows,
    azurerm_monitor_data_collection_rule_association.aks,
    azurerm_monitor_diagnostic_setting.web,
    azurerm_monitor_diagnostic_setting.aks,
    azurerm_monitor_diagnostic_setting.key_vault,
    azurerm_monitor_diagnostic_setting.activity,
    azurerm_sentinel_log_analytics_workspace_onboarding.soc,
    azurerm_linux_web_app.web,
    azurerm_kubernetes_cluster.lab,
    azurerm_role_assignment.aks_admin,
    azurerm_role_assignment.key_vault_secrets,
    azurerm_key_vault_secret.linux_ssh_public_key,
  ]
}
