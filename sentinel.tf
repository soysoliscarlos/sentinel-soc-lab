variable "enable_sentinel_analytics" {
  description = "Crea el workbook, las reglas analiticas LAB-Pxx y la regla de automatizacion que correlacionan la actividad marcada SOC-L2-Pxx. Requiere Sentinel habilitado sobre el workspace."
  type        = bool
  default     = false
  nullable    = false
}

locals {
  # Cada regla genera incidentes LAB-Pxx a partir de los marcadores SOC-L2 que produce Invoke-SocLabLogGeneration.ps1.
  # Se configuran con severidades Medium/High para garantizar visibilidad directa en Defender XDR (Priority Score >= 15)
  # y frecuencia PT5M para evaluacion rapida tras la ejecucion del script.
  sentinel_rules = {
    P02 = {
      display_name    = "LAB-P02 - Fallos de autenticacion Windows (Fuerza Bruta)"
      description     = "Multiples eventos 4625 con cuentas inexistentes soc-l2-p02-* generados por la prueba P02."
      severity        = "High"
      tactics         = ["CredentialAccess"]
      query_frequency = "PT5M"
      query_period    = "PT30M"
      query           = <<-KQL
        SecurityEvent
        | where EventID == 4625 and TargetUserName startswith "soc-l2-p02"
        | summarize FailedAttempts = count() by Computer, TargetUserName, IpAddress, bin(TimeGenerated, 5m)
        | where FailedAttempts >= 2
      KQL
      entities = [
        { entity_type = "Account", mappings = [{ identifier = "Name", column_name = "TargetUserName" }] },
        { entity_type = "Host", mappings = [{ identifier = "HostName", column_name = "Computer" }] },
        { entity_type = "IP", mappings = [{ identifier = "Address", column_name = "IpAddress" }] },
      ]
    }
    P15 = {
      display_name    = "LAB-P15 - Gestion anomala de cuentas y grupos AD"
      description     = "Altas, cambios y bajas de cuentas y grupos desechables SOCp15/SOCg15 de la prueba P15."
      severity        = "High"
      tactics         = ["Persistence", "PrivilegeEscalation"]
      query_frequency = "PT5M"
      query_period    = "PT15M"
      query           = <<-KQL
        SecurityEvent
        | where EventID in (4720, 4722, 4724, 4725, 4726, 4727, 4728, 4729, 4730, 4732, 4733, 4738)
        | where TargetUserName startswith "SOCp15" or TargetUserName startswith "SOCg15" or MemberName has "SOCp15"
        | project TimeGenerated, Computer, EventID, Activity, SubjectUserName, TargetUserName, MemberName
      KQL
      entities = [
        { entity_type = "Account", mappings = [{ identifier = "Name", column_name = "TargetUserName" }] },
        { entity_type = "Host", mappings = [{ identifier = "HostName", column_name = "Computer" }] },
      ]
    }
    P03 = {
      display_name    = "LAB-P03 - Ejecucion de procesos sospechosos en Windows"
      description     = "Eventos 4688 con la linea de comandos marcada SOC-L2-P03 de la prueba P03."
      severity        = "Medium"
      tactics         = ["Execution"]
      query_frequency = "PT5M"
      query_period    = "PT15M"
      query           = <<-KQL
        SecurityEvent
        | where EventID == 4688 and CommandLine has "SOC-L2-P03"
        | project TimeGenerated, Computer, SubjectUserName, NewProcessName, CommandLine, ParentProcessName
      KQL
      entities = [
        { entity_type = "Account", mappings = [{ identifier = "Name", column_name = "SubjectUserName" }] },
        { entity_type = "Host", mappings = [{ identifier = "HostName", column_name = "Computer" }] },
      ]
    }
    P04B = {
      display_name    = "LAB-P04B - Fuerza bruta SSH y su en Linux"
      description     = "Intentos SSH y su fallidos con usuarios inexistentes socp04* de la prueba P04B."
      severity        = "High"
      tactics         = ["CredentialAccess"]
      query_frequency = "PT5M"
      query_period    = "PT15M"
      query           = <<-KQL
        Syslog
        | where ProcessName in ("sshd", "su") and SyslogMessage has "socp04"
        | project TimeGenerated, Computer, Facility, ProcessName, SyslogMessage
      KQL
      entities = [
        { entity_type = "Host", mappings = [{ identifier = "HostName", column_name = "Computer" }] },
      ]
    }
    P05 = {
      display_name    = "LAB-P05 - Escaneo web y reconocimiento en App Service"
      description     = "Rutas y metodos sospechosos tipo path traversal/inyeccion con User-Agent SOC-L2-Lab de la prueba P05."
      severity        = "Medium"
      tactics         = ["Discovery", "InitialAccess"]
      query_frequency = "PT5M"
      query_period    = "PT15M"
      query           = <<-KQL
        AppServiceHTTPLogs
        | where UserAgent startswith "SOC-L2-Lab" and ScStatus >= 400
        | project TimeGenerated, CIp, CsMethod, CsUriStem, ScStatus
      KQL
      entities = [
        { entity_type = "IP", mappings = [{ identifier = "Address", column_name = "CIp" }] },
      ]
    }
    P07 = {
      display_name    = "LAB-P07 - Acceso no autorizado o denegado en Key Vault"
      description     = "Lectura fallida de secreto inexistente soc-l2-p07 de la prueba P07 en Key Vault."
      severity        = "Medium"
      tactics         = ["Discovery", "CredentialAccess"]
      query_frequency = "PT5M"
      query_period    = "PT15M"
      query           = <<-KQL
        AZKVAuditLogs
        | where OperationName has "Secret" and RequestUri has "soc-l2-p07"
        | where ResultSignature != "OK" or toint(HttpStatusCode) >= 400
        | project TimeGenerated, CallerIpAddress, OperationName, ResultSignature, HttpStatusCode, RequestUri
      KQL
      entities = [
        { entity_type = "IP", mappings = [{ identifier = "Address", column_name = "CallerIpAddress" }] },
      ]
    }
    P08 = {
      display_name    = "LAB-P08 - Modificaciones administrativas en Kubernetes"
      description     = "Creacion o modificacion de objetos en el namespace soc-l2-p08 de la prueba P08 en AKS."
      severity        = "Medium"
      tactics         = ["Persistence", "Execution"]
      query_frequency = "PT5M"
      query_period    = "PT15M"
      query           = <<-KQL
        AKSAuditAdmin
        | where RequestUri has "soc-l2-p08" and Verb in ("create", "update", "delete")
        | project TimeGenerated, Verb, RequestUri, Codigo = tostring(parse_json(tostring(ResponseStatus)).code), Usuario = tostring(parse_json(tostring(User)).username)
      KQL
      entities        = []
    }
    P09 = {
      display_name    = "LAB-P09 - Modificacion sospechosa de etiquetas ARM"
      description     = "Alteracion no autorizada de etiquetas SOCPrueba en recursos de Azure registrada en AzureActivity."
      severity        = "Medium"
      tactics         = ["Impact"]
      query_frequency = "PT5M"
      query_period    = "PT15M"
      query           = <<-KQL
        AzureActivity
        | where OperationNameValue startswith "MICROSOFT.RESOURCES/TAGS/"
        | where ActivityStatusValue in ("Success", "Succeeded", "Accepted")
        | where Properties has "SOCPrueba" or Properties has "SOC-L2-P09"
        | project TimeGenerated, Caller, CallerIpAddress, OperationNameValue, ActivityStatusValue, _ResourceId
      KQL
      entities = [
        { entity_type = "Account", mappings = [{ identifier = "Name", column_name = "Caller" }] },
        { entity_type = "IP", mappings = [{ identifier = "Address", column_name = "CallerIpAddress" }] },
      ]
    }
    P10 = {
      display_name    = "LAB-P10 - Evento de advertencia en pods de AKS"
      description     = "Deteccion de eventos Warning en Kubernetes generados por despliegues de pods anomalos en AKS."
      severity        = "Medium"
      tactics         = ["Execution"]
      query_frequency = "PT5M"
      query_period    = "PT15M"
      query           = <<-KQL
        KubeEvents
        | where Namespace startswith "soc-l2-p08" and KubeEventType == "Warning"
        | project TimeGenerated, Computer, Namespace, Name, ObjectKind, Reason, Message
      KQL
      entities = [
        { entity_type = "Host", mappings = [{ identifier = "HostName", column_name = "Computer" }] },
      ]
    }
    P11 = {
      display_name    = "LAB-P11 - Peticion HTTP anomala en servidor Apache"
      description     = "Peticiones web marcadas con ruta sospechosa registradas por Apache en Syslog local6."
      severity        = "Medium"
      tactics         = ["InitialAccess", "Discovery"]
      query_frequency = "PT5M"
      query_period    = "PT15M"
      query           = <<-KQL
        Syslog
        | where Facility == "local6" and SyslogMessage has "SOC-L2-P11"
        | project TimeGenerated, Computer, Facility, ProcessName, SyslogMessage
      KQL
      entities = [
        { entity_type = "Host", mappings = [{ identifier = "HostName", column_name = "Computer" }] },
      ]
    }
    P12 = {
      display_name    = "LAB-P12 - Peticion HTTP sospechosa en servidor IIS"
      description     = "Sondeo web o acceso anomalo registrado en W3CIISLog de Windows Server con marcador de prueba."
      severity        = "Medium"
      tactics         = ["InitialAccess", "Discovery"]
      query_frequency = "PT5M"
      query_period    = "PT15M"
      query           = <<-KQL
        W3CIISLog
        | where csUriStem has "SOC-L2-P12"
        | project TimeGenerated, Computer, sSiteName, csMethod, csUriStem, scStatus, cIP, csUserAgent
      KQL
      entities = [
        { entity_type = "Host", mappings = [{ identifier = "HostName", column_name = "Computer" }] },
        { entity_type = "IP", mappings = [{ identifier = "Address", column_name = "cIP" }] },
      ]
    }
    P13 = {
      display_name    = "LAB-P13 - Fallo de autenticacion en base de datos PostgreSQL"
      description     = "Intentos fallidos de conexion o autenticacion con usuario invalido en PostgreSQL registrados en Syslog local5."
      severity        = "Medium"
      tactics         = ["CredentialAccess"]
      query_frequency = "PT5M"
      query_period    = "PT15M"
      query           = <<-KQL
        Syslog
        | where Facility == "local5" and SyslogMessage has "soc_l2_p13"
        | project TimeGenerated, Computer, ProcessName, SeverityLevel, SyslogMessage
      KQL
      entities = [
        { entity_type = "Host", mappings = [{ identifier = "HostName", column_name = "Computer" }] },
      ]
    }
    P14 = {
      display_name    = "LAB-P14 - Evento sospechoso en Application Log de Windows"
      description     = "Evento de nivel advertencia o anomalo registrado por la fuente SOC-L2-Lab en el log Application."
      severity        = "Medium"
      tactics         = ["DefenseEvasion"]
      query_frequency = "PT5M"
      query_period    = "PT15M"
      query           = <<-KQL
        Event
        | where Source == "SOC-L2-Lab" and RenderedDescription has "SOC-L2-P14"
        | project TimeGenerated, Computer, EventLog, EventLevelName, EventID, RenderedDescription
      KQL
      entities = [
        { entity_type = "Host", mappings = [{ identifier = "HostName", column_name = "Computer" }] },
      ]
    }
  }
}

resource "random_uuid" "sentinel_rule" {
  for_each = var.enable_sentinel_analytics ? local.sentinel_rules : {}
}

resource "random_uuid" "sentinel_workbook" {
  count = var.enable_sentinel_analytics ? 1 : 0
}

resource "random_uuid" "sentinel_automation" {
  count = var.enable_sentinel_analytics ? 1 : 0
}

resource "azurerm_sentinel_alert_rule_scheduled" "lab" {
  for_each = var.enable_sentinel_analytics ? local.sentinel_rules : {}

  name                       = random_uuid.sentinel_rule[each.key].result
  log_analytics_workspace_id = azurerm_log_analytics_workspace.soc.id
  display_name               = each.value.display_name
  description                = each.value.description
  severity                   = each.value.severity
  tactics                    = each.value.tactics
  enabled                    = true
  query                      = each.value.query
  query_frequency            = each.value.query_frequency
  query_period               = each.value.query_period
  trigger_operator           = "GreaterThan"
  trigger_threshold          = 0
  suppression_enabled        = false

  event_grouping {
    aggregation_method = "AlertPerResult"
  }

  incident {
    create_incident_enabled = true

    grouping {
      enabled                 = true
      entity_matching_method  = "AllEntities"
      lookback_duration       = "PT1H"
      reopen_closed_incidents = false
    }
  }

  dynamic "entity_mapping" {
    for_each = each.value.entities
    content {
      entity_type = entity_mapping.value.entity_type

      dynamic "field_mapping" {
        for_each = entity_mapping.value.mappings
        content {
          identifier  = field_mapping.value.identifier
          column_name = field_mapping.value.column_name
        }
      }
    }
  }

  depends_on = [azurerm_sentinel_log_analytics_workspace_onboarding.soc]
}

resource "azurerm_application_insights_workbook" "soc" {
  count = var.enable_sentinel_analytics ? 1 : 0

  name                = random_uuid.sentinel_workbook[0].result
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  display_name        = "SOC L2 Lab - Eventos de seguridad generados"
  source_id           = lower(azurerm_log_analytics_workspace.soc.id)
  category            = "sentinel"
  data_json           = file("${path.module}/files/soc-workbook.json")
  tags                = local.tags
}

resource "azurerm_sentinel_automation_rule" "lab" {
  count = var.enable_sentinel_analytics ? 1 : 0

  name                       = random_uuid.sentinel_automation[0].result
  log_analytics_workspace_id = azurerm_log_analytics_workspace.soc.id
  display_name               = "LAB - Etiquetar y enriquecer incidentes del taller"
  order                      = 1
  enabled                    = true
  triggers_on                = "Incidents"
  triggers_when              = "Created"

  condition_json = jsonencode([
    {
      conditionType = "Property"
      conditionProperties = {
        propertyName   = "IncidentTitle"
        operator       = "Contains"
        propertyValues = ["LAB-"]
      }
    }
  ])

  action_incident {
    order  = 1
    labels = ["SOC-L2-Lab"]
  }

  dynamic "action_playbook" {
    for_each = var.enable_sentinel_playbooks ? local.sentinel_playbook_actions : {}
    content {
      order        = action_playbook.value.order
      logic_app_id = jsondecode(azurerm_resource_group_template_deployment.playbook[action_playbook.key].output_content).logicAppResourceId.value
      tenant_id    = data.azurerm_client_config.current.tenant_id
    }
  }

  depends_on = [azurerm_sentinel_alert_rule_scheduled.lab]
}
