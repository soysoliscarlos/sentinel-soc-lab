variable "enable_log_generation" {
  description = "Runs scripts/Invoke-SocLabLogGeneration.ps1 at the end of apply to generate benign marked activity across VMs, App Service, Key Vault, ARM, and AKS. Requires authorization."
  type        = bool
  default     = false
  nullable    = false
}

variable "log_generation_tests" {
  description = "Test groups executed by the log generation script."
  type        = list(string)
  default     = ["All"]
  nullable    = false

  validation {
    condition = length(var.log_generation_tests) > 0 && alltrue([
      for test in var.log_generation_tests :
      contains(["All", "Windows", "Linux", "WebServers", "AppService", "KeyVault", "Arm", "Aks"], test)
    ])
    error_message = "Use All or a list containing Windows, Linux, WebServers, AppService, KeyVault, Arm, and Aks."
  }
}

variable "log_generation_wait_minutes" {
  description = "Maximum minutes to wait for Heartbeat from enabled VMs and KubePodInventory from AKS (if present) before generating activity."
  type        = number
  default     = 30
  nullable    = false

  validation {
    condition     = var.log_generation_wait_minutes >= 1 && var.log_generation_wait_minutes <= 60
    error_message = "Source wait timeout must be between 1 and 60 minutes."
  }
}

variable "log_generation_initial_delay_seconds" {
  description = "Additional warm-up delay in seconds so newly created diagnostic settings begin exporting logs."
  type        = number
  default     = 300
  nullable    = false

  validation {
    condition     = var.log_generation_initial_delay_seconds >= 0 && var.log_generation_initial_delay_seconds <= 1800
    error_message = "Initial delay must be between 0 and 1800 seconds."
  }
}

variable "log_generation_verify" {
  description = "Polls the workspace until each marker is visible; pending ingestion is reported without failing apply."
  type        = bool
  default     = true
  nullable    = false
}

variable "log_generation_trigger" {
  description = "Arbitrary string; changing it re-runs log generation on the next apply."
  type        = string
  default     = "initial"
  nullable    = false
}

resource "terraform_data" "log_generation" {
  count = var.enable_log_generation ? 1 : 0

  # Re-runs only when a connected telemetry source, script, test list, or manual trigger changes.
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

  # Final deployment step: resources, Windows auditing, Ansible, data collection, and Sentinel onboarding are ready.
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
