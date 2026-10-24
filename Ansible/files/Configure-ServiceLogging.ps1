[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Ansible.Changed = $false
Import-Module WebAdministration -ErrorAction Stop
$filter = "system.applicationHost/sites/site[@name='Default Web Site']/logFile"
$properties = [ordered]@{
    enabled = $true
    logFormat = 'W3C'
    directory = 'C:\inetpub\logs\LogFiles'
    period = 'Hourly'
    localTimeRollover = $false
    logTargetW3C = 'File'
}
foreach ($name in $properties.Keys) {
    # IIS devuelve ConfigurationAttribute para algunos atributos y valores simples para otros.
    $raw = Get-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter $filter -Name $name
    $current = $raw
    if ($null -ne $raw -and $raw -isnot [string] -and $raw -isnot [ValueType] -and $raw.PSObject.Properties['Value']) {
        $current = $raw.Value
    }
    if ([string]$current -ne [string]$properties[$name]) {
        $Ansible.Changed = $true
        if (!$Ansible.CheckMode) {
            Set-WebConfigurationProperty -PSPath 'MACHINE/WEBROOT/APPHOST' -Filter $filter -Name $name -Value $properties[$name]
        }
    }
}
$site = Get-Website -Name 'Default Web Site'
if ($site.id -ne 1) { throw 'La DCR IIS espera el sitio del laboratorio W3SVC1.' }

# GUID independientes del idioma: cuentas, grupos, Kerberos, NTLM y cambios AD.
$subcategories = @(
    '{0CCE9235-69AE-11D9-BED3-505054503030}',
    '{0CCE9236-69AE-11D9-BED3-505054503030}',
    '{0CCE9237-69AE-11D9-BED3-505054503030}',
    '{0CCE923C-69AE-11D9-BED3-505054503030}',
    '{0CCE923F-69AE-11D9-BED3-505054503030}',
    '{0CCE9240-69AE-11D9-BED3-505054503030}',
    '{0CCE9242-69AE-11D9-BED3-505054503030}'
)
function Get-AuditValue {
    param([string]$Guid)
    # /backup incluye el valor numerico; /get /r solo devuelve texto localizado.
    $path = Join-Path ([IO.Path]::GetTempPath()) ("soc-audit-" + [guid]::NewGuid() + '.csv')
    try {
        & auditpol.exe /backup "/file:$path" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "No se pudo consultar la politica de auditoria $Guid." }
        $rows = @(Import-Csv -LiteralPath $path | Where-Object {
            @($_.PSObject.Properties)[3].Value -eq $Guid
        })
        if ($rows.Count -ne 1) { throw "Respuesta de auditpol inesperada para $Guid." }
        $values = @($rows[0].PSObject.Properties | ForEach-Object { $_.Value })
        $value = 0
        if (![int]::TryParse($values[-1], [ref]$value)) {
            throw "auditpol no devolvio el valor numerico de la politica $Guid."
        }
        return $value
    }
    finally {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
}
foreach ($guid in $subcategories) {
    if ((Get-AuditValue $guid) -ne 3) {
        $Ansible.Changed = $true
        if (!$Ansible.CheckMode) {
            & auditpol.exe /set "/subcategory:$guid" /success:enable /failure:enable
            if ($LASTEXITCODE -ne 0) { throw "No se pudo activar la auditoria $guid." }
            if ((Get-AuditValue $guid) -ne 3) { throw "No se confirmo la politica de auditoria $guid." }
        }
    }
}
foreach ($channel in @('Directory Service', 'DNS Server', 'DFS Replication')) {
    $log = Get-WinEvent -ListLog $channel -ErrorAction Stop
    if (!$log.IsEnabled) {
        $Ansible.Changed = $true
        if (!$Ansible.CheckMode) {
            & wevtutil.exe sl $channel /e:true
            if ($LASTEXITCODE -ne 0) { throw "No se pudo activar el canal $channel." }
        }
    }
}
