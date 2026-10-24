locals {
  sentinel_hunting_queries = {
    HUNT01 = {
      display_name = "HUNT-01 - Ejecucion Anomala de Procesos y LOLBAS (T1059.001 / T1218)"
      description  = "Caza proactiva de procesos sospechosos o binarios de confianza (PowerShell, Cmd, Certutil, Wmic) con parametros de ofuscacion o evasion."
      tactics      = "Execution,DefenseEvasion"
      query        = <<-KQL
        SecurityEvent
        | where EventID == 4688
        | extend ProcessName = tostring(split(NewProcessName, "\\")[-1])
        | extend ParentProcess = tostring(split(ParentProcessName, "\\")[-1])
        | extend CommandLineLower = tolower(CommandLine)
        | where ProcessName in~ ("powershell.exe", "pwsh.exe", "cmd.exe", "certutil.exe", "wmic.exe", "bitsadmin.exe", "mshta.exe", "cscript.exe", "wscript.exe", "rundll32.exe")
        | where CommandLineLower has_any (
            "-enc", "-encodedcommand", "bypass", "hidden", "downloadstring", 
            "invoke-webrequest", "urlcache", "-decode", "http:", "https:",
            "soc-l2-p03", "soc-l2"
          )
        | project TimeGenerated, Computer, SubjectUserName, ProcessName, ParentProcess, CommandLine
        | order by TimeGenerated desc
      KQL
    }
    HUNT02 = {
      display_name = "HUNT-02 - Movimiento Lateral y Accesos Interactivos Anomalos (T1078 / T1021)"
      description  = "Caza proactiva de patrones de autenticacion anomala, fuerza bruta interna o sesiones RDP/Red entre servidores y origenes no autorizados."
      tactics      = "LateralMovement,CredentialAccess"
      query        = <<-KQL
        SecurityEvent
        | where EventID in (4624, 4625)
        | extend LogonTypeDesc = case(
            LogonType == 2, "Interactive",
            LogonType == 3, "Network",
            LogonType == 10, "RemoteInteractive (RDP)",
            LogonType == 4, "Batch",
            LogonType == 5, "Service",
            tostring(LogonType)
          )
        | summarize
            TotalAttempts = count(),
            SuccessCount = countif(EventID == 4624),
            FailureCount = countif(EventID == 4625),
            DistinctTargets = dcount(TargetUserName),
            UsersTargeted = make_set(TargetUserName, 10),
            LogonTypes = make_set(LogonTypeDesc, 5)
          by IpAddress, Computer, bin(TimeGenerated, 1h)
        | where FailureCount >= 2 or (SuccessCount > 0 and IpAddress !in ("", "-", "127.0.0.1", "::1"))
        | extend HuntingFinding = case(
            FailureCount >= 3, "Posible Fuerza Bruta o Spraying",
            SuccessCount > 0 and IpAddress !in ("", "-", "127.0.0.1"), "Acceso Remoto para Investigar",
            "Actividad Relevante"
          )
        | project TimeGenerated, Computer, IpAddress, HuntingFinding, TotalAttempts, FailureCount, SuccessCount, UsersTargeted, LogonTypes
        | order by TimeGenerated desc
      KQL
    }
  }
}

resource "azurerm_log_analytics_saved_search" "hunting" {
  for_each = var.enable_sentinel_analytics ? local.sentinel_hunting_queries : {}

  name                       = "${var.name_prefix}-hunt-${lower(each.key)}"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.soc.id
  category                   = "Hunting Queries"
  display_name               = each.value.display_name
  query                      = each.value.query

  tags = {
    Description = each.value.description
    Tactics     = each.value.tactics
    Environment = "lab"
    ManagedBy   = "Terraform"
    Project     = "SOC-L2"
  }
}
