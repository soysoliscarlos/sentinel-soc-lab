mock_provider "azurerm" {
  override_during = plan

  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "11111111-1111-1111-1111-111111111111"
      object_id = "55555555-5555-5555-5555-555555555555"
    }
  }

  mock_resource "azurerm_key_vault" {
    defaults = {
      id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/soc-unit-test-rg/providers/Microsoft.KeyVault/vaults/soc-unit-test-kv"
    }
  }

  mock_resource "azurerm_private_dns_zone" {
    defaults = {
      id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/soc-unit-test-rg/providers/Microsoft.Network/privateDnsZones/privatelink.vaultcore.azure.net"
    }
  }

  mock_resource "azurerm_virtual_network" {
    defaults = {
      id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/soc-unit-test-rg/providers/Microsoft.Network/virtualNetworks/lab"
    }
  }

  mock_resource "azurerm_log_analytics_workspace" {
    defaults = {
      id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/soc-unit-test-rg/providers/Microsoft.OperationalInsights/workspaces/soc-unit-test-law"
    }
  }

  mock_resource "azurerm_linux_virtual_machine" {
    defaults = {
      id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/soc-unit-test-rg/providers/Microsoft.Compute/virtualMachines/linux"
    }
  }

  mock_resource "azurerm_windows_virtual_machine" {
    defaults = {
      id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/soc-unit-test-rg/providers/Microsoft.Compute/virtualMachines/windows"
    }
  }

  mock_resource "azurerm_linux_web_app" {
    defaults = {
      id               = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/soc-unit-test-rg/providers/Microsoft.Web/sites/web"
      default_hostname = "soc-unit-test-web.azurewebsites.net"
    }
  }

  mock_resource "azurerm_kubernetes_cluster" {
    defaults = {
      id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/soc-unit-test-rg/providers/Microsoft.ContainerService/managedClusters/aks"
      oms_agent = {
        oms_agent_identity = []
      }
    }
  }

  mock_resource "azurerm_resource_group_template_deployment" {
    defaults = {
      output_content = "{\"logicAppResourceId\":{\"value\":\"/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/soc-unit-test-rg/providers/Microsoft.Logic/workflows/pb\"},\"principalId\":{\"value\":\"66666666-6666-6666-6666-666666666666\"}}"
    }
  }
}

mock_provider "azuread" {
  override_during = plan
  mock_data "azuread_service_principal" {
    defaults = {
      object_id = "77777777-7777-7777-7777-777777777777"
    }
  }
}

override_resource {
  target          = azurerm_subnet.private_endpoint
  override_during = plan
  values = {
    id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/soc-unit-test-rg/providers/Microsoft.Network/virtualNetworks/lab/subnets/snet-private-endpoints"
  }
}

override_resource {
  target          = azurerm_public_ip.vm["linux"]
  override_during = plan
  values = {
    id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/soc-unit-test-rg/providers/Microsoft.Network/publicIPAddresses/linux"
  }
}

override_resource {
  target          = azurerm_public_ip.vm["windows"]
  override_during = plan
  values = {
    id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/soc-unit-test-rg/providers/Microsoft.Network/publicIPAddresses/windows"
  }
}

override_resource {
  target          = azurerm_monitor_data_collection_rule.linux
  override_during = plan
  values = {
    id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/soc-unit-test-rg/providers/Microsoft.Insights/dataCollectionRules/linux"
  }
}

override_resource {
  target          = azurerm_monitor_data_collection_rule.windows
  override_during = plan
  values = {
    id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/soc-unit-test-rg/providers/Microsoft.Insights/dataCollectionRules/windows"
  }
}

override_resource {
  target          = azurerm_monitor_data_collection_rule.aks
  override_during = plan
  values = {
    id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/soc-unit-test-rg/providers/Microsoft.Insights/dataCollectionRules/aks"
  }
}

mock_provider "tls" {
  override_during = plan
  mock_resource "tls_private_key" {
    defaults = {
      public_key_openssh = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCdvyVwvWNWlyXbQCjbjyiWHEUtWlkTO10X89P2+RuX7NJtsbJzETOAfwAQB5VvGyaiB2k9cwv5nIy7cReva17N2ZMi4r/zqtA//vtFjiYPa7lLsSb/5nz22mdd8/O21TIr2eH6gMbhlnfOfhcNe/QES40MbGm85fjTSxm7tUhzGWOegUy1Oea9Gterbtrcukqkh71m5piwOUk+D4JIVRSoldKiFXSdIrrl+V/HFvrz7wt7BTPsgOjPYXJep/nbi5+1JvoNcqdoYHEKimGZteQu+xWyWZWO7qLLRZg4U1tKGn37E1OPhB2ATRDHmIogrQpUXrOOBy22et7v76/2BPZJ mock-public-key"
    }
  }
}

mock_provider "random" {
  override_during = plan
  mock_resource "random_password" {
    defaults = {
      result = "MockOnly!Abcd1234#Efgh5678$Ijkl9012"
    }
  }
}

variables {
  create_aks                = true
  create_app_service        = true
  create_linux_vm           = true
  create_windows_vm         = true
  enable_log_generation     = false
  enable_ansible            = false
  enable_sentinel_analytics = false
  enable_sentinel_playbooks = false
  enable_sentinel_notebooks = false
  subscription_id           = "11111111-1111-1111-1111-111111111111"
  name_prefix               = "soc-unit-test"
  admin_source_cidr         = "203.0.113.10/32"
}

run "lab_defaults_and_access" {
  command = plan

  assert {
    condition = (
      azurerm_resource_group.lab.location == "eastus2" &&
      azurerm_service_plan.web[0].os_type == "Linux" &&
      azurerm_service_plan.web[0].sku_name == "B1" &&
      azurerm_kubernetes_cluster.lab[0].sku_tier == "Free" &&
      azurerm_kubernetes_cluster.lab[0].default_node_pool[0].node_count == 2 &&
      azurerm_kubernetes_cluster.lab[0].default_node_pool[0].vm_size == "Standard_D4s_v6"
    )
    error_message = "El perfil debe conservar la region, App Service B1 y AKS Free con dos nodos D4s_v6."
  }

  assert {
    condition = (
      length(azurerm_public_ip.vm) == 2 &&
      alltrue([for ip in azurerm_public_ip.vm : ip.sku == "Standard" && ip.allocation_method == "Static"]) &&
      alltrue([for key, nic in azurerm_network_interface.vm : nic.ip_configuration[0].public_ip_address_id == azurerm_public_ip.vm[key].id])
    )
    error_message = "Ambas VM deben tener su propia IP publica Standard estatica asociada a la NIC."
  }

  assert {
    condition = alltrue([
      for key, nsg in azurerm_network_security_group.vm :
      length(nsg.security_rule) == 2 &&
      length([for rule in nsg.security_rule : rule if rule.access == "Allow" && rule.source_address_prefix == var.admin_source_cidr && rule.destination_port_range == local.vm[key].admin_port]) == 1 &&
      length([for rule in nsg.security_rule : rule if rule.access == "Deny" && rule.priority == 200 && rule.direction == "Inbound"]) == 1
    ])
    error_message = "SSH/RDP solo deben aceptar el CIDR aprobado; el resto del trafico entrante debe denegarse."
  }

  assert {
    condition = (
      azurerm_linux_virtual_machine.linux[0].disable_password_authentication &&
      azurerm_kubernetes_cluster.lab[0].local_account_disabled &&
      azurerm_kubernetes_cluster.lab[0].azure_active_directory_role_based_access_control[0].azure_rbac_enabled &&
      azurerm_kubernetes_cluster.lab[0].api_server_access_profile[0].authorized_ip_ranges == toset([var.admin_source_cidr]) &&
      azurerm_role_assignment.aks_admin[0].principal_id == data.azurerm_client_config.current.object_id &&
      azurerm_role_assignment.aks_admin[0].scope == azurerm_kubernetes_cluster.lab[0].id &&
      azurerm_role_assignment.aks_admin[0].role_definition_name == "Azure Kubernetes Service RBAC Cluster Admin" &&
      azurerm_linux_web_app.web[0].https_only &&
      !azurerm_linux_web_app.web[0].ftp_publish_basic_authentication_enabled &&
      !azurerm_linux_web_app.web[0].webdeploy_publish_basic_authentication_enabled
    )
    error_message = "Debe conservarse SSH por clave, AKS con Entra/RBAC y App Service sin publicacion basica."
  }
}

run "ansible_opt_in_and_network" {
  command = plan

  variables {
    enable_ansible = true
  }

  assert {
    condition = (
      length(terraform_data.ansible) == 1 &&
      azurerm_virtual_machine_extension.windows_audit[0].type == "CustomScriptExtension" &&
      length(jsondecode(azurerm_virtual_machine_extension.windows_audit[0].settings).commandToExecute) <= 8191 &&
      strcontains(local.windows_configuration_script, file("${path.module}/scripts/Configure-WindowsAudit.ps1")) &&
      strcontains(local.windows_configuration_script, "OpenSSH.Server") &&
      length(random_password.dsrm) == 1 &&
      azurerm_key_vault_secret.dsrm[0].name == "windows-dsrm-password"
    )
    error_message = "Ansible debe incluir bootstrap Windows, ejecucion Terraform y un secreto DSRM recuperable."
  }

  assert {
    condition = (
      azurerm_network_interface.vm["windows"].ip_configuration[0].private_ip_address_allocation == "Static" &&
      azurerm_network_interface.vm["windows"].ip_configuration[0].private_ip_address == "10.20.1.10" &&
      azurerm_windows_virtual_machine.windows[0].os_disk[0].caching == "None" &&
      local.ansible_config.domain_name == "lab.example.test"
    )
    error_message = "El DC debe conservar una IP privada fija, disco sin cache y el dominio confirmado."
  }

  assert {
    condition = alltrue([
      for key, nsg in azurerm_network_security_group.vm :
      length(nsg.security_rule) == (key == "windows" ? 4 : 3) &&
      alltrue([for rule in nsg.security_rule : rule.source_address_prefix == var.admin_source_cidr if rule.access == "Allow"]) &&
      length([for rule in nsg.security_rule : rule if rule.destination_port_range == "80" && rule.access == "Allow"]) == 1 &&
      length([for rule in nsg.security_rule : rule if contains(["5432", "3389", "22", "80"], rule.destination_port_range) == false && rule.access == "Allow"]) == 0
    ])
    error_message = "Solo se permite administracion y HTTP desde el CIDR aprobado, nunca PostgreSQL ni puertos AD."
  }
}

run "ansible_disabled_by_default" {
  command = plan

  assert {
    condition = (
      length(terraform_data.ansible) == 0 &&
      length(random_password.dsrm) == 0 &&
      length(azurerm_key_vault_secret.dsrm) == 0 &&
      length(one(azurerm_monitor_data_collection_rule.windows[0].data_sources).iis_log) == 0 &&
      !contains(one(one(azurerm_monitor_data_collection_rule.linux[0].data_sources).syslog).facility_names, "local5") &&
      azurerm_network_interface.vm["windows"].ip_configuration[0].private_ip_address_allocation == "Dynamic" &&
      azurerm_windows_virtual_machine.windows[0].os_disk[0].caching == "ReadWrite"
    )
    error_message = "Sin consentimiento explicito no debe prepararse SSH, promover Windows ni ejecutarse Ansible."
  }
}

run "service_logs_to_existing_workspace" {
  command = plan

  variables {
    enable_ansible = true
  }

  assert {
    condition = (
      toset(one(one(azurerm_monitor_data_collection_rule.linux[0].data_sources).syslog).facility_names) == toset(["auth", "authpriv", "daemon", "syslog", "kern", "local5", "local6"]) &&
      contains(one(one(azurerm_monitor_data_collection_rule.linux[0].data_sources).syslog).log_levels, "Info") &&
      toset(one(azurerm_monitor_data_collection_rule.linux[0].data_flow).streams) == toset(["Microsoft-Syslog"]) &&
      one(azurerm_monitor_data_collection_rule.linux[0].destinations).log_analytics[0].workspace_resource_id == azurerm_log_analytics_workspace.soc.id &&
      one(azurerm_monitor_data_collection_rule.linux[0].data_flow).destinations == tolist(["soc"])
    )
    error_message = "PostgreSQL local5 y Apache local6 deben enviarse por Syslog a soc sin perder las facilities previas."
  }

  assert {
    condition = (
      length(one(azurerm_monitor_data_collection_rule.windows[0].data_sources).iis_log) == 1 &&
      one(one(azurerm_monitor_data_collection_rule.windows[0].data_sources).iis_log).log_directories == tolist(["C:\\inetpub\\logs\\LogFiles\\W3SVC1"]) &&
      one(one(azurerm_monitor_data_collection_rule.windows[0].data_sources).iis_log).streams == tolist(["Microsoft-W3CIISLog"]) &&
      toset(one(azurerm_monitor_data_collection_rule.windows[0].data_flow).streams) == toset(["Microsoft-SecurityEvent", "Microsoft-Event", "Microsoft-W3CIISLog"]) &&
      one(azurerm_monitor_data_collection_rule.windows[0].destinations).log_analytics[0].workspace_resource_id == azurerm_log_analytics_workspace.soc.id &&
      one(azurerm_monitor_data_collection_rule.windows[0].data_flow).destinations == tolist(["soc"])
    )
    error_message = "IIS W3C debe leerse del sitio 1 y usar el mismo destino Log Analytics con stream compatible."
  }

  assert {
    condition = (
      length([for source in one(azurerm_monitor_data_collection_rule.windows[0].data_sources).windows_event_log : source if source.name == "adds-services" && toset(source.streams) == toset(["Microsoft-Event"]) && toset(source.x_path_queries) == toset([
        "Directory Service!*[System[(Level=1 or Level=2 or Level=3)]]",
        "DNS Server!*[System[(Level=1 or Level=2 or Level=3)]]",
        "DFS Replication!*[System[(Level=1 or Level=2 or Level=3)]]",
      ])]) == 1 &&
      length(local.windows_security_event_ids) == length(distinct(local.windows_security_event_ids)) &&
      alltrue([for id in [4625, 4688, 4720, 4728, 4738, 4742, 4768, 4769, 4771, 4776, 5136] : contains(local.windows_security_event_ids, id)]) &&
      length([for source in one(azurerm_monitor_data_collection_rule.windows[0].data_sources).windows_event_log : source if source.name == "security" && alltrue([
        for query in source.x_path_queries : length(regexall("EventID=", query)) <= 20
      ]) && length(source.x_path_queries) == ceil(length(local.windows_security_event_ids) / 20)]) == 1
    )
    error_message = "AD DS debe conservar canales de servicio y auditoria de seguridad sin duplicar IDs ni superar 20 expresiones por XPath."
  }

  assert {
    condition = alltrue([
      for name in ["linux-logging.yml", "files/Configure-ServiceLogging.ps1", "files/30-soc-apache.conf"] :
      contains(local.ansible_files, name)
    ])
    error_message = "Los cambios en la configuracion de logs deben volver a ejecutar Ansible desde Terraform."
  }
}

run "custom_skus_and_vm_sizes" {
  command = plan

  variables {
    linux_vm_size       = "Standard_D4s_v6"
    windows_vm_size     = "Standard_D4s_v6"
    linux_image_sku     = "22_04-lts"
    windows_image_sku   = "2022-datacenter"
    linux_os_disk_sku   = "StandardSSD_LRS"
    windows_os_disk_sku = "Premium_LRS"
    aks_sku_tier        = "Standard"
    aks_node_vm_size    = "Standard_D8s_v6"
    app_service_sku     = "S1"
    key_vault_sku       = "premium"
  }

  assert {
    condition = (
      azurerm_linux_virtual_machine.linux[0].size == var.linux_vm_size &&
      azurerm_windows_virtual_machine.windows[0].size == var.windows_vm_size &&
      azurerm_linux_virtual_machine.linux[0].source_image_reference[0].sku == var.linux_image_sku &&
      azurerm_windows_virtual_machine.windows[0].source_image_reference[0].sku == var.windows_image_sku &&
      azurerm_linux_virtual_machine.linux[0].os_disk[0].storage_account_type == var.linux_os_disk_sku &&
      azurerm_windows_virtual_machine.windows[0].os_disk[0].storage_account_type == var.windows_os_disk_sku &&
      azurerm_kubernetes_cluster.lab[0].sku_tier == var.aks_sku_tier &&
      azurerm_kubernetes_cluster.lab[0].default_node_pool[0].vm_size == var.aks_node_vm_size &&
      azurerm_kubernetes_cluster.lab[0].default_node_pool[0].os_sku == var.aks_os_sku &&
      azurerm_kubernetes_cluster.lab[0].network_profile[0].load_balancer_sku == var.aks_load_balancer_sku &&
      azurerm_service_plan.web[0].sku_name == var.app_service_sku &&
      azurerm_key_vault.lab.sku_name == var.key_vault_sku &&
      azurerm_log_analytics_workspace.soc.sku == var.log_workspace_sku &&
      alltrue([for ip in azurerm_public_ip.vm : ip.sku == var.public_ip_sku])
    )
    error_message = "Todos los SKU y tamanos deben proceder de las variables, sin valores fijos en los recursos."
  }
}

run "app_service_direct_https_access" {
  command = plan

  assert {
    condition = (
      azurerm_linux_web_app.web[0].public_network_access_enabled &&
      azurerm_linux_web_app.web[0].https_only &&
      one(azurerm_linux_web_app.web[0].site_config).minimum_tls_version == "1.2" &&
      one(azurerm_linux_web_app.web[0].site_config).ip_restriction_default_action == "Allow" &&
      length(one(azurerm_linux_web_app.web[0].site_config).ip_restriction) == 0 &&
      !one(azurerm_linux_web_app.web[0].site_config).scm_use_main_ip_restriction &&
      one(azurerm_linux_web_app.web[0].site_config).scm_ip_restriction_default_action == "Allow" &&
      !azurerm_linux_web_app.web[0].ftp_publish_basic_authentication_enabled &&
      !azurerm_linux_web_app.web[0].webdeploy_publish_basic_authentication_enabled &&
      output.app_service_url == "https://soc-unit-test-web.azurewebsites.net"
    )
    error_message = "App Service debe recuperar acceso directo HTTPS sin restricciones del Gateway y conservar TLS y publicacion sin autenticacion basica."
  }
}

run "centralized_telemetry" {
  command = plan

  assert {
    condition     = length(azurerm_kubernetes_cluster.lab[0].oms_agent[0].oms_agent_identity) == 0
    error_message = "La prueba debe reproducir Container Insights con autenticacion administrada sin identidad propia del complemento."
  }

  assert {
    condition = (
      azurerm_sentinel_log_analytics_workspace_onboarding.soc.workspace_id == azurerm_log_analytics_workspace.soc.id &&
      azurerm_kubernetes_cluster.lab[0].oms_agent[0].log_analytics_workspace_id == azurerm_log_analytics_workspace.soc.id &&
      azurerm_kubernetes_cluster.lab[0].oms_agent[0].msi_auth_for_monitoring_enabled &&
      alltrue([
        for dcr in concat(azurerm_monitor_data_collection_rule.linux, azurerm_monitor_data_collection_rule.windows, azurerm_monitor_data_collection_rule.aks) :
        dcr.destinations[0].log_analytics[0].workspace_resource_id == azurerm_log_analytics_workspace.soc.id
      ]) &&
      alltrue([
        for diagnostic in concat(azurerm_monitor_diagnostic_setting.web, azurerm_monitor_diagnostic_setting.aks, [azurerm_monitor_diagnostic_setting.activity, azurerm_monitor_diagnostic_setting.key_vault]) :
        diagnostic.log_analytics_workspace_id == azurerm_log_analytics_workspace.soc.id
      ])
    )
    error_message = "Sentinel, AMA, Container Insights y diagnosticos deben usar el mismo workspace."
  }

  assert {
    condition = (
      azurerm_virtual_machine_extension.linux_monitor[0].virtual_machine_id == azurerm_linux_virtual_machine.linux[0].id &&
      azurerm_virtual_machine_extension.windows_monitor[0].virtual_machine_id == azurerm_windows_virtual_machine.windows[0].id &&
      azurerm_monitor_data_collection_rule_association.linux[0].target_resource_id == azurerm_linux_virtual_machine.linux[0].id &&
      azurerm_monitor_data_collection_rule_association.linux[0].data_collection_rule_id == azurerm_monitor_data_collection_rule.linux[0].id &&
      azurerm_monitor_data_collection_rule_association.windows[0].target_resource_id == azurerm_windows_virtual_machine.windows[0].id &&
      azurerm_monitor_data_collection_rule_association.windows[0].data_collection_rule_id == azurerm_monitor_data_collection_rule.windows[0].id &&
      azurerm_monitor_data_collection_rule_association.aks[0].target_resource_id == azurerm_kubernetes_cluster.lab[0].id &&
      azurerm_monitor_data_collection_rule_association.aks[0].data_collection_rule_id == azurerm_monitor_data_collection_rule.aks[0].id &&
      azurerm_monitor_diagnostic_setting.web[0].target_resource_id == azurerm_linux_web_app.web[0].id &&
      azurerm_monitor_diagnostic_setting.aks[0].target_resource_id == azurerm_kubernetes_cluster.lab[0].id &&
      azurerm_monitor_diagnostic_setting.key_vault.target_resource_id == azurerm_key_vault.lab.id &&
      azurerm_monitor_diagnostic_setting.activity.target_resource_id == "/subscriptions/${var.subscription_id}"
    )
    error_message = "Cada agente, DCR y diagnostico debe estar asociado al recurso correcto."
  }

  assert {
    condition = (
      contains(one(azurerm_monitor_data_collection_rule.linux[0].data_flow).streams, "Microsoft-Syslog") &&
      contains(one(azurerm_monitor_data_collection_rule.windows[0].data_flow).streams, "Microsoft-SecurityEvent") &&
      contains(one(azurerm_monitor_data_collection_rule.windows[0].data_flow).streams, "Microsoft-Event") &&
      contains(one(azurerm_monitor_data_collection_rule.aks[0].data_flow).streams, "Microsoft-ContainerLogV2") &&
      length(azurerm_monitor_diagnostic_setting.activity.enabled_log) == 8 &&
      length([for log in azurerm_monitor_diagnostic_setting.web[0].enabled_log : log if log.category == "AppServiceHTTPLogs"]) == 1 &&
      length([for log in azurerm_monitor_diagnostic_setting.aks[0].enabled_log : log if log.category == "kube-audit-admin"]) == 1 &&
      azurerm_log_analytics_workspace.soc.daily_quota_gb == 1 &&
      azurerm_log_analytics_workspace.soc.retention_in_days == 30 &&
      !azurerm_log_analytics_workspace.soc.local_authentication_enabled
    )
    error_message = "Deben recolectarse Syslog, SecurityEvent, Event, contenedores, HTTP, auditoria AKS y Azure Activity con cuota y retencion."
  }

  assert {
    condition = alltrue([
      for diagnostic in concat(azurerm_monitor_diagnostic_setting.web, azurerm_monitor_diagnostic_setting.aks, [azurerm_monitor_diagnostic_setting.key_vault]) :
      diagnostic.log_analytics_destination_type == "Dedicated"
    ])
    error_message = "Los diagnosticos deben conservar tablas dedicadas para que las consultas de Sentinel no cambien de esquema."
  }

  assert {
    condition = (
      toset([for log in azurerm_monitor_diagnostic_setting.web[0].enabled_log : log.category]) == toset(["AppServiceHTTPLogs", "AppServiceConsoleLogs", "AppServiceAuditLogs", "AppServiceIPSecAuditLogs", "AppServicePlatformLogs"]) &&
      toset([for log in azurerm_monitor_diagnostic_setting.aks[0].enabled_log : log.category]) == toset(["kube-audit-admin", "kube-apiserver", "kube-controller-manager", "kube-scheduler", "cluster-autoscaler", "guard"]) &&
      toset([for log in azurerm_monitor_diagnostic_setting.key_vault.enabled_log : log.category]) == toset(["AuditEvent"]) &&
      toset([for log in azurerm_monitor_diagnostic_setting.activity.enabled_log : log.category]) == toset(["Administrative", "Security", "ServiceHealth", "Alert", "Recommendation", "Policy", "Autoscale", "ResourceHealth"])
    )
    error_message = "No debe perderse ninguna categoria prevista, incluida autenticacion guard de AKS y auditoria de Key Vault."
  }

  assert {
    condition = alltrue([
      for dcr in concat(azurerm_monitor_data_collection_rule.linux, azurerm_monitor_data_collection_rule.windows, azurerm_monitor_data_collection_rule.aks) :
      one(dcr.destinations).log_analytics[0].name == "soc" &&
      one(dcr.data_flow).destinations == tolist(["soc"])
    ])
    error_message = "Cada flujo debe apuntar al destino soc definido en su propia DCR, no solo declarar un workspace."
  }

  assert {
    condition = (
      toset(one(one(azurerm_monitor_data_collection_rule.linux[0].data_sources).syslog).streams) == toset(["Microsoft-Syslog"]) &&
      toset(one(one(azurerm_monitor_data_collection_rule.linux[0].data_sources).syslog).facility_names) == toset(["auth", "authpriv", "daemon", "syslog", "kern"]) &&
      length([for source in one(azurerm_monitor_data_collection_rule.windows[0].data_sources).windows_event_log : source if toset(source.streams) == toset(["Microsoft-SecurityEvent"]) && anytrue([for query in source.x_path_queries : strcontains(query, "EventID=4625") && strcontains(query, "EventID=4688")])]) == 1 &&
      length([for source in one(azurerm_monitor_data_collection_rule.windows[0].data_sources).windows_event_log : source if toset(source.streams) == toset(["Microsoft-Event"]) && length(source.x_path_queries) == 2]) == 1 &&
      toset(one(one(azurerm_monitor_data_collection_rule.aks[0].data_sources).extension).streams) == toset(["Microsoft-ContainerLogV2", "Microsoft-KubeEvents", "Microsoft-KubePodInventory"]) &&
      toset(one(azurerm_monitor_data_collection_rule.aks[0].data_flow).streams) == toset(["Microsoft-ContainerLogV2", "Microsoft-KubeEvents", "Microsoft-KubePodInventory"]) &&
      jsondecode(one(one(azurerm_monitor_data_collection_rule.aks[0].data_sources).extension).extension_json).dataCollectionSettings.enableContainerLogV2
    )
    error_message = "Las fuentes deben emitir los streams esperados; un data_flow sin fuente compatible no garantiza recoleccion."
  }

  assert {
    condition = (
      azurerm_virtual_machine_extension.windows_audit[0].virtual_machine_id == azurerm_windows_virtual_machine.windows[0].id &&
      azurerm_virtual_machine_extension.windows_audit[0].publisher == "Microsoft.Compute" &&
      azurerm_virtual_machine_extension.windows_audit[0].type == "CustomScriptExtension" &&
      jsondecode(azurerm_virtual_machine_extension.windows_audit[0].settings).commandToExecute == "powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ${textencodebase64(file("${path.module}/scripts/Configure-WindowsAudit.ps1"), "UTF-16LE")}"
    )
    error_message = "La politica de auditoria debe ejecutarse en la VM Windows con el script versionado y codificacion UTF-16LE."
  }
}

run "key_vault_and_generated_ssh_key" {
  command = plan

  assert {
    condition = (
      tls_private_key.linux[0].algorithm == "RSA" &&
      tls_private_key.linux[0].rsa_bits == 4096 &&
      azurerm_ssh_public_key.linux[0].public_key == trimspace(tls_private_key.linux[0].public_key_openssh) &&
      one(azurerm_linux_virtual_machine.linux[0].admin_ssh_key).public_key == azurerm_ssh_public_key.linux[0].public_key &&
      azurerm_key_vault_secret.linux_ssh_public_key[0].value == azurerm_ssh_public_key.linux[0].public_key &&
      azurerm_key_vault_secret.linux_ssh_public_key[0].key_vault_id == azurerm_key_vault.lab.id
    )
    error_message = "La misma publica RSA generada debe registrarse en Azure, autorizar la VM y guardarse en Key Vault; nunca la privada."
  }

  assert {
    condition = (
      azurerm_key_vault.lab.name == "soc-unit-test-kv01" &&
      azurerm_key_vault.lab.rbac_authorization_enabled &&
      azurerm_key_vault.lab.public_network_access_enabled &&
      azurerm_key_vault.lab.network_acls[0].default_action == "Deny" &&
      azurerm_key_vault.lab.network_acls[0].bypass == "None" &&
      azurerm_key_vault.lab.network_acls[0].ip_rules == toset([var.admin_source_cidr]) &&
      !azurerm_key_vault.lab.purge_protection_enabled &&
      azurerm_role_assignment.key_vault_secrets.scope == azurerm_key_vault.lab.id &&
      azurerm_role_assignment.key_vault_secrets.role_definition_name == "Key Vault Secrets Officer" &&
      azurerm_role_assignment.key_vault_secrets.principal_id == data.azurerm_client_config.current.object_id
    )
    error_message = "El vault debe exigir RBAC, restringir el endpoint publico al CIDR administrativo y autorizar al ejecutor para escribir secretos."
  }

  assert {
    condition = (
      azurerm_subnet.private_endpoint.address_prefixes == tolist(["10.20.3.0/24"]) &&
      azurerm_private_endpoint.key_vault.subnet_id == azurerm_subnet.private_endpoint.id &&
      azurerm_private_endpoint.key_vault.private_service_connection[0].private_connection_resource_id == azurerm_key_vault.lab.id &&
      azurerm_private_endpoint.key_vault.private_service_connection[0].subresource_names == tolist(["vault"]) &&
      !azurerm_private_endpoint.key_vault.private_service_connection[0].is_manual_connection &&
      azurerm_private_dns_zone.key_vault.name == "privatelink.vaultcore.azure.net" &&
      one(azurerm_private_endpoint.key_vault.private_dns_zone_group).private_dns_zone_ids == tolist([azurerm_private_dns_zone.key_vault.id]) &&
      azurerm_private_dns_zone_virtual_network_link.key_vault.virtual_network_id == azurerm_virtual_network.lab.id &&
      azurerm_private_dns_zone_virtual_network_link.key_vault.private_dns_zone_id == azurerm_private_dns_zone.key_vault.id &&
      azurerm_monitor_diagnostic_setting.key_vault.target_resource_id == azurerm_key_vault.lab.id &&
      one(azurerm_monitor_diagnostic_setting.key_vault.enabled_log).category == "AuditEvent"
    )
    error_message = "El Private Endpoint debe enlazar el vault, su subred y DNS privado; la auditoria debe dirigirse a Sentinel."
  }
}

run "reject_private_admin_cidr" {
  command = plan
  variables {
    admin_source_cidr = "10.10.0.0/16"
  }
  expect_failures = [var.admin_source_cidr]
}

run "reject_private_admin_host" {
  command = plan
  variables {
    admin_source_cidr = "192.168.1.10/32"
  }
  expect_failures = [var.admin_source_cidr]
}

run "reject_open_admin_cidr" {
  command = plan
  variables {
    admin_source_cidr = "0.0.0.0/0"
  }
  expect_failures = [var.admin_source_cidr]
}

run "reject_invalid_admin_cidr" {
  command = plan
  variables {
    admin_source_cidr = "not-a-cidr"
  }
  expect_failures = [var.admin_source_cidr]
}

run "generated_windows_password_in_key_vault" {
  command = plan

  assert {
    condition = (
      random_password.windows_admin[0].length == 32 &&
      random_password.windows_admin[0].upper &&
      random_password.windows_admin[0].lower &&
      random_password.windows_admin[0].numeric &&
      random_password.windows_admin[0].special &&
      random_password.windows_admin[0].min_upper == 4 &&
      random_password.windows_admin[0].min_lower == 4 &&
      random_password.windows_admin[0].min_numeric == 4 &&
      random_password.windows_admin[0].min_special == 4 &&
      random_password.windows_admin[0].override_special == "!#$%&*()-_=+?"
    )
    error_message = "La contrasena debe generarse con 32 caracteres y al menos cuatro de cada categoria."
  }

  assert {
    condition = (
      azurerm_windows_virtual_machine.windows[0].admin_username == "socadmin" &&
      azurerm_windows_virtual_machine.windows[0].admin_password == random_password.windows_admin[0].result &&
      azurerm_key_vault_secret.windows_admin_password[0].value == random_password.windows_admin[0].result &&
      azurerm_key_vault_secret.windows_admin_password[0].name == "windows-admin-password" &&
      azurerm_key_vault_secret.windows_admin_password[0].key_vault_id == azurerm_key_vault.lab.id
    )
    error_message = "Windows y el secreto del vault deben recibir exactamente la misma contrasena generada."
  }
}

run "reject_single_system_node" {
  command = plan
  variables {
    aks_node_count = 1
  }
  expect_failures = [var.aks_node_count]
}

run "reject_key_vault_consecutive_hyphens" {
  command = plan
  variables {
    name_prefix = "soc--lab"
  }
  expect_failures = [var.name_prefix]
}

run "reject_long_key_vault_suffix" {
  command = plan
  variables {
    key_vault_name_suffix = "kv-01"
  }
  expect_failures = [var.key_vault_name_suffix]
}

run "log_generation_disabled_by_default" {
  command = plan

  assert {
    condition     = length(terraform_data.log_generation) == 0
    error_message = "Sin consentimiento explicito Terraform no debe generar actividad de prueba."
  }
}

run "log_generation_after_telemetry" {
  command = plan

  variables {
    enable_ansible        = true
    enable_log_generation = true
    log_generation_tests  = ["Windows", "Aks"]
  }

  assert {
    condition = (
      length(terraform_data.log_generation) == 1 &&
      contains(terraform_data.log_generation[0].triggers_replace, "Windows,Aks") &&
      contains(terraform_data.log_generation[0].triggers_replace, filesha256("${path.module}/scripts/Invoke-SocLabLogGeneration.ps1"))
    )
    error_message = "La generacion de logs debe activarse solo por opt-in y reejecutarse si cambian las pruebas o el script."
  }
}

run "reject_unknown_log_generation_test" {
  command = plan
  variables {
    log_generation_tests = ["Windows", "Exploit"]
  }
  expect_failures = [var.log_generation_tests]
}

run "all_optional_components_disabled" {
  command = plan

  variables {
    create_app_service    = false
    create_linux_vm       = false
    create_windows_vm     = false
    create_aks            = false
    enable_log_generation = true
  }

  assert {
    condition = alltrue([
      for instances in [
        azurerm_service_plan.web, azurerm_linux_web_app.web,
        azurerm_linux_virtual_machine.linux, azurerm_windows_virtual_machine.windows,
        azurerm_kubernetes_cluster.lab, azurerm_user_assigned_identity.aks,
        azurerm_role_assignment.aks_network, azurerm_role_assignment.aks_admin,
        azurerm_subnet.vm, azurerm_subnet.aks,
        azurerm_log_analytics_solution.container_insights,
        azurerm_virtual_machine_extension.linux_monitor,
        azurerm_virtual_machine_extension.windows_monitor,
        azurerm_virtual_machine_extension.windows_audit,
        azurerm_monitor_data_collection_rule.linux,
        azurerm_monitor_data_collection_rule.windows,
        azurerm_monitor_data_collection_rule.aks,
        azurerm_monitor_data_collection_rule_association.linux,
        azurerm_monitor_data_collection_rule_association.windows,
        azurerm_monitor_data_collection_rule_association.aks,
        azurerm_monitor_diagnostic_setting.web, azurerm_monitor_diagnostic_setting.aks,
        tls_private_key.linux, azurerm_ssh_public_key.linux,
        random_password.windows_admin, random_password.dsrm,
        azurerm_key_vault_secret.linux_ssh_public_key,
        azurerm_key_vault_secret.windows_admin_password,
        azurerm_key_vault_secret.dsrm, terraform_data.ansible,
      ] : length(instances) == 0
    ])
    error_message = "No debe quedar ningun recurso exclusivo al desactivar todos los componentes opcionales."
  }

  assert {
    condition = (
      length(azurerm_public_ip.vm) == 0 &&
      length(azurerm_network_interface.vm) == 0 &&
      length(azurerm_network_security_group.vm) == 0 &&
      length(azurerm_network_interface_security_group_association.vm) == 0 &&
      output.aks_cluster_name == null &&
      output.app_service_url == null &&
      output.linux_public_ip == null &&
      output.windows_public_ip == null &&
      output.linux_ssh_private_key == null &&
      output.linux_ssh_public_key_secret_id == null &&
      output.windows_admin_password_secret_id == null &&
      azurerm_sentinel_log_analytics_workspace_onboarding.soc.workspace_id == azurerm_log_analytics_workspace.soc.id &&
      azurerm_monitor_diagnostic_setting.key_vault.target_resource_id == azurerm_key_vault.lab.id &&
      length(terraform_data.log_generation) == 1 &&
      alltrue([for index in range(3, 8) : terraform_data.log_generation[0].triggers_replace[index] == null])
    )
    error_message = "Los outputs deben ser null, la red exclusiva debe desaparecer y los servicios compartidos y logs deben seguir disponibles."
  }
}

run "linux_disabled_independently" {
  command = plan

  variables {
    create_linux_vm       = false
    enable_log_generation = true
  }

  assert {
    condition = (
      length(azurerm_linux_virtual_machine.linux) == 0 &&
      length(azurerm_windows_virtual_machine.windows) == 1 &&
      length(azurerm_kubernetes_cluster.lab) == 1 &&
      length(azurerm_linux_web_app.web) == 1 &&
      keys(azurerm_public_ip.vm) == ["windows"] &&
      keys(azurerm_network_interface.vm) == ["windows"] &&
      keys(azurerm_network_security_group.vm) == ["windows"] &&
      length(azurerm_subnet.vm) == 1 &&
      length(azurerm_monitor_data_collection_rule.linux) == 0 &&
      length(azurerm_monitor_data_collection_rule_association.linux) == 0 &&
      length(azurerm_virtual_machine_extension.linux_monitor) == 0 &&
      length(tls_private_key.linux) == 0 &&
      length(azurerm_ssh_public_key.linux) == 0 &&
      length(azurerm_key_vault_secret.linux_ssh_public_key) == 0 &&
      output.linux_public_ip == null &&
      local.ansible_config == null
    )
    error_message = "Desactivar Linux debe retirar sus dependencias sin afectar Windows, AKS ni App Service."
  }
}

run "windows_disabled_independently" {
  command = plan

  variables {
    create_windows_vm     = false
    enable_log_generation = true
  }

  assert {
    condition = (
      length(azurerm_windows_virtual_machine.windows) == 0 &&
      length(azurerm_linux_virtual_machine.linux) == 1 &&
      length(azurerm_kubernetes_cluster.lab) == 1 &&
      length(azurerm_linux_web_app.web) == 1 &&
      keys(azurerm_public_ip.vm) == ["linux"] &&
      keys(azurerm_network_interface.vm) == ["linux"] &&
      keys(azurerm_network_security_group.vm) == ["linux"] &&
      length(azurerm_subnet.vm) == 1 &&
      length(azurerm_monitor_data_collection_rule.windows) == 0 &&
      length(azurerm_monitor_data_collection_rule_association.windows) == 0 &&
      length(azurerm_virtual_machine_extension.windows_monitor) == 0 &&
      length(azurerm_virtual_machine_extension.windows_audit) == 0 &&
      length(random_password.windows_admin) == 0 &&
      length(azurerm_key_vault_secret.windows_admin_password) == 0 &&
      output.windows_public_ip == null &&
      local.ansible_config == null
    )
    error_message = "Desactivar Windows debe retirar sus dependencias sin afectar Linux, AKS ni App Service."
  }
}

run "app_service_disabled_independently" {
  command = plan

  variables {
    create_app_service    = false
    enable_ansible        = true
    enable_log_generation = true
  }

  assert {
    condition = (
      length(azurerm_service_plan.web) == 0 &&
      length(azurerm_linux_web_app.web) == 0 &&
      length(azurerm_monitor_diagnostic_setting.web) == 0 &&
      output.app_service_url == null &&
      length(azurerm_linux_virtual_machine.linux) == 1 &&
      length(azurerm_windows_virtual_machine.windows) == 1 &&
      length(azurerm_kubernetes_cluster.lab) == 1 &&
      length(terraform_data.ansible) == 1
    )
    error_message = "Desactivar App Service debe retirar tambien su plan y diagnosticos, sin afectar los otros componentes."
  }
}

run "aks_disabled_independently" {
  command = plan

  variables {
    create_aks            = false
    enable_ansible        = true
    enable_log_generation = true
  }

  assert {
    condition = (
      length(azurerm_kubernetes_cluster.lab) == 0 &&
      length(azurerm_subnet.aks) == 0 &&
      length(azurerm_user_assigned_identity.aks) == 0 &&
      length(azurerm_role_assignment.aks_network) == 0 &&
      length(azurerm_role_assignment.aks_admin) == 0 &&
      length(azurerm_log_analytics_solution.container_insights) == 0 &&
      length(azurerm_monitor_data_collection_rule.aks) == 0 &&
      length(azurerm_monitor_data_collection_rule_association.aks) == 0 &&
      length(azurerm_monitor_diagnostic_setting.aks) == 0 &&
      output.aks_cluster_name == null &&
      length(azurerm_linux_virtual_machine.linux) == 1 &&
      length(azurerm_windows_virtual_machine.windows) == 1 &&
      length(azurerm_linux_web_app.web) == 1 &&
      length(terraform_data.ansible) == 1
    )
    error_message = "Desactivar AKS debe retirar todas sus dependencias exclusivas sin afectar las VM ni App Service."
  }
}

run "reject_ansible_without_linux" {
  command = plan
  variables {
    enable_ansible  = true
    create_linux_vm = false
  }
  expect_failures = [var.enable_ansible]
}

run "reject_ansible_without_windows" {
  command = plan
  variables {
    enable_ansible    = true
    create_windows_vm = false
  }
  expect_failures = [var.enable_ansible]
}

run "reject_ansible_without_vms" {
  command = plan
  variables {
    enable_ansible    = true
    create_linux_vm   = false
    create_windows_vm = false
  }
  expect_failures = [var.enable_ansible]
}

run "sentinel_content_disabled_by_default" {
  command = plan

  assert {
    condition = (
      length(azurerm_sentinel_alert_rule_scheduled.lab) == 0 &&
      length(azurerm_application_insights_workbook.soc) == 0 &&
      length(azurerm_sentinel_automation_rule.lab) == 0 &&
      length(azurerm_resource_group_template_deployment.playbook) == 0 &&
      length(azurerm_machine_learning_workspace.soc) == 0
    )
    error_message = "El contenido de Sentinel no debe crearse sin habilitar los interruptores correspondientes."
  }
}

run "sentinel_analytics_enabled" {
  command = plan

  variables {
    enable_sentinel_analytics = true
  }

  assert {
    condition = (
      length(azurerm_sentinel_alert_rule_scheduled.lab) == 13 &&
      azurerm_sentinel_alert_rule_scheduled.lab["P02"].display_name == "LAB-P02 - Fallos de autenticacion Windows (Fuerza Bruta)" &&
      azurerm_sentinel_alert_rule_scheduled.lab["P02"].log_analytics_workspace_id == azurerm_log_analytics_workspace.soc.id &&
      azurerm_sentinel_alert_rule_scheduled.lab["P15"].severity == "High" &&
      length(azurerm_application_insights_workbook.soc) == 1 &&
      length(azurerm_sentinel_automation_rule.lab) == 1 &&
      length(azurerm_resource_group_template_deployment.playbook) == 0
    )
    error_message = "Con enable_sentinel_analytics deben existir las reglas LAB-Pxx, el workbook y la regla de automatizacion, sin playbooks."
  }
}

run "sentinel_playbooks_enabled" {
  command = plan

  variables {
    enable_sentinel_analytics = true
    enable_sentinel_playbooks = true
  }

  assert {
    condition = (
      length(azurerm_resource_group_template_deployment.playbook) == 2 &&
      length(azurerm_role_assignment.playbook_responder) == 2 &&
      length(azurerm_role_assignment.sentinel_automation) == 1 &&
      azurerm_role_assignment.sentinel_automation[0].role_definition_name == "Microsoft Sentinel Automation Contributor"
    )
    error_message = "Con enable_sentinel_playbooks deben desplegarse los dos playbooks y sus asignaciones de rol."
  }
}

run "reject_playbooks_without_analytics" {
  command = plan

  variables {
    enable_sentinel_analytics = false
    enable_sentinel_playbooks = true
  }
  expect_failures = [var.enable_sentinel_playbooks]
}

run "sentinel_notebooks_enabled" {
  command = plan

  variables {
    enable_sentinel_notebooks = true
  }

  assert {
    condition = (
      length(azurerm_machine_learning_workspace.soc) == 1 &&
      length(azurerm_machine_learning_compute_instance.soc) == 1 &&
      azurerm_machine_learning_compute_instance.soc[0].virtual_machine_size == "Standard_DS2_v2" &&
      length(azurerm_storage_account.ml) == 1 &&
      length(azurerm_application_insights.ml) == 1 &&
      length(azurerm_key_vault.ml) == 1 &&
      length(azurerm_role_assignment.notebook_log_reader) == 1
    )
    error_message = "Con enable_sentinel_notebooks deben crearse el workspace de Azure ML, la compute instance y sus dependencias."
  }
}
