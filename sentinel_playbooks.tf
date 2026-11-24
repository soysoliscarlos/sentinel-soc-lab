variable "enable_sentinel_playbooks" {
  description = "Deploys two Logic App playbooks invoked by the automation rule on LAB-Pxx incidents: one adds an enrichment comment and the other sets triage status and labels. Requires enable_sentinel_analytics."
  type        = bool
  default     = false
  nullable    = false

  validation {
    condition     = !var.enable_sentinel_playbooks || var.enable_sentinel_analytics
    error_message = "enable_sentinel_playbooks requires enable_sentinel_analytics = true."
  }
}

locals {
  # Execution order inside the automation rule (action_incident uses order 1).
  sentinel_playbook_actions = {
    enrich = { order = 2, file = "playbook-enrich-comment.json", suffix = "pb-enrich" }
    triage = { order = 3, file = "playbook-tag-triage.json", suffix = "pb-triage" }
  }

  # Microsoft Sentinel Managed API ID for managed-identity playbook connections.
  sentinel_managed_api_id = "/subscriptions/${var.subscription_id}/providers/Microsoft.Web/locations/${azurerm_resource_group.lab.location}/managedApis/azuresentinel"

  # Public first-party application ID for "Azure Security Insights" executing automation rules.
  sentinel_service_client_id = "98785600-1bb7-4fb9-b9fa-19afe2c8a360"
}

data "azuread_service_principal" "sentinel" {
  count = var.enable_sentinel_playbooks ? 1 : 0

  client_id = local.sentinel_service_client_id
}

resource "azurerm_resource_group_template_deployment" "playbook" {
  for_each = var.enable_sentinel_playbooks ? local.sentinel_playbook_actions : {}

  name                = "${var.name_prefix}-${each.value.suffix}"
  resource_group_name = azurerm_resource_group.lab.name
  deployment_mode     = "Incremental"
  template_content    = file("${path.module}/files/${each.value.file}")

  parameters_content = jsonencode({
    playbookName  = { value = "${var.name_prefix}-${each.value.suffix}" }
    location      = { value = azurerm_resource_group.lab.location }
    sentinelApiId = { value = local.sentinel_managed_api_id }
  })

  tags = local.tags

  depends_on = [azurerm_sentinel_log_analytics_workspace_onboarding.soc]
}

# Allows each Logic App to read and update Sentinel incidents using its managed identity.
resource "azurerm_role_assignment" "playbook_responder" {
  for_each = var.enable_sentinel_playbooks ? local.sentinel_playbook_actions : {}

  scope                = azurerm_resource_group.lab.id
  role_definition_name = "Microsoft Sentinel Responder"
  principal_id         = jsondecode(azurerm_resource_group_template_deployment.playbook[each.key].output_content).principalId.value
}

# Allows Sentinel automation rules to invoke Logic App playbooks in the resource group.
resource "azurerm_role_assignment" "sentinel_automation" {
  count = var.enable_sentinel_playbooks ? 1 : 0

  scope                = azurerm_resource_group.lab.id
  role_definition_name = "Microsoft Sentinel Automation Contributor"
  principal_id         = data.azuread_service_principal.sentinel[0].object_id
}
