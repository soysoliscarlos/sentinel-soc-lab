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
    # IIS returns ConfigurationAttribute wrappers for some properties and raw values for others.
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
if ($site.id -ne 1) { throw 'The IIS DCR expects Default Web Site with site ID 1 (W3SVC1).' }

# Language-independent subcategory GUIDs: accounts, groups, Kerberos, NTLM, and AD DS changes.
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
    # /backup exports numeric Inclusion Setting values; /get /r only emits localized text.
    $path = Join-Path ([IO.Path]::GetTempPath()) ("soc-audit-" + [guid]::NewGuid() + '.csv')
    try {
        & auditpol.exe /backup "/file:$path" | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Failed to query audit policy $Guid." }
        $rows = @(Import-Csv -LiteralPath $path | Where-Object {
            @($_.PSObject.Properties)[3].Value -eq $Guid
        })
        if ($rows.Count -ne 1) { throw "Unexpected auditpol output for $Guid." }
        $values = @($rows[0].PSObject.Properties | ForEach-Object { $_.Value })
        $value = 0
        if (![int]::TryParse($values[-1], [ref]$value)) {
            throw "auditpol did not return a numeric setting value for policy $Guid."
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
            if ($LASTEXITCODE -ne 0) { throw "Failed to enable audit subcategory $guid." }
            if ((Get-AuditValue $guid) -ne 3) { throw "Failed to verify audit policy $guid." }
        }
    }
}
foreach ($channel in @('Directory Service', 'DNS Server', 'DFS Replication')) {
    $log = Get-WinEvent -ListLog $channel -ErrorAction Stop
    if (!$log.IsEnabled) {
        $Ansible.Changed = $true
        if (!$Ansible.CheckMode) {
            & wevtutil.exe sl $channel /e:true
            if ($LASTEXITCODE -ne 0) { throw "Failed to enable event log channel $channel." }
        }
    }
}
