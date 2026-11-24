$ErrorActionPreference = 'Stop'
$global:SocLogTest = @{
    Iis = @{}
    Policies = @{}
    Channels = @{}
    Writes = 0
    FailBackup = $false
    FailSet = $false
    TempFiles = @()
}
$global:Ansible = @{ Changed = $false; CheckMode = $false }
$scriptPath = Join-Path (Split-Path $PSScriptRoot) 'files\Configure-ServiceLogging.ps1'

function Import-Module { param($Name, $ErrorAction) }
function Get-WebConfigurationProperty {
    param($PSPath, $Filter, $Name)
    $value = $global:SocLogTest.Iis[$Name]
    # Matches live IIS behavior: raw strings/enums for some attributes, ConfigurationAttribute objects for booleans.
    if ($Name -in @('logFormat', 'period', 'logTargetW3C', 'directory')) { return $value }
    return [pscustomobject]@{ Value = $value }
}
function Set-WebConfigurationProperty {
    param($PSPath, $Filter, $Name, $Value)
    $global:SocLogTest.Iis[$Name] = $Value
    $global:SocLogTest.Writes++
}
function Get-Website { param($Name); return @{ id = 1 } }
function Get-WinEvent {
    param($ListLog, $ErrorAction)
    return @{ IsEnabled = [bool]$global:SocLogTest.Channels[$ListLog] }
}
function wevtutil.exe {
    $global:SocLogTest.Channels[$args[1]] = $true
    $global:SocLogTest.Writes++
    $global:LASTEXITCODE = 0
}
function auditpol.exe {
    $global:LASTEXITCODE = 0
    if ($args[0] -eq '/backup') {
        if ($global:SocLogTest.FailBackup) { $global:LASTEXITCODE = 1; return }
        $path = $args[1].Substring('/file:'.Length)
        $global:SocLogTest.TempFiles += $path
        # Simulates arbitrary localized CSV headers: only column positions for GUID and numeric setting are stable.
        $rows = foreach ($guid in @(
            '{0CCE9235-69AE-11D9-BED3-505054503030}',
            '{0CCE9236-69AE-11D9-BED3-505054503030}',
            '{0CCE9237-69AE-11D9-BED3-505054503030}',
            '{0CCE923C-69AE-11D9-BED3-505054503030}',
            '{0CCE923F-69AE-11D9-BED3-505054503030}',
            '{0CCE9240-69AE-11D9-BED3-505054503030}',
            '{0CCE9242-69AE-11D9-BED3-505054503030}'
        )) {
            [pscustomobject][ordered]@{
                MachineName = 'LAB'
                PolicyTarget = 'System'
                Subcategory = 'LocalizedName'
                SubcategoryGuid = $guid
                InclusionSetting = 'Success and Failure'
                ExclusionSetting = ''
                SettingValue = [int]$global:SocLogTest.Policies[$guid]
            }
        }
        $rows | Export-Csv -LiteralPath $path -NoTypeInformation
    }
    elseif ($args[0] -eq '/set') {
        if ($global:SocLogTest.FailSet) { $global:LASTEXITCODE = 1; return }
        $global:SocLogTest.Policies[$args[1].Substring('/subcategory:'.Length)] = 3
        $global:SocLogTest.Writes++
    }
    else { throw 'Unexpected auditpol operation.' }
}

try {
    & $scriptPath
    if (!$global:Ansible.Changed -or $global:SocLogTest.Writes -ne 16) {
        throw 'Expected six IIS properties, seven audit policies, and three event channels to be configured.'
    }
    if ($global:SocLogTest.Iis.logFormat -ne 'W3C' -or
        $global:SocLogTest.Iis.period -ne 'Hourly' -or
        $global:SocLogTest.Iis.directory -ne 'C:\inetpub\logs\LogFiles') {
        throw 'IIS logging configuration does not match the DCR source.'
    }
    $global:SocLogTest.Writes = 0
    & $scriptPath
    if ($global:Ansible.Changed -or $global:SocLogTest.Writes -ne 0) {
        throw 'Service logging configuration is not idempotent.'
    }
    $global:SocLogTest.Iis.period = 'Daily'
    $global:Ansible.CheckMode = $true
    & $scriptPath
    if (!$global:Ansible.Changed -or $global:SocLogTest.Writes -ne 0) {
        throw 'Check mode must detect drift without writing changes.'
    }
    $global:Ansible.CheckMode = $false
    $global:SocLogTest.FailBackup = $true
    $failed = $false
    try { & $scriptPath }
    catch {
        if ($_.Exception.Message -notlike 'Failed to query audit policy*') { throw }
        $failed = $true
    }
    if (!$failed) { throw 'auditpol backup failure was swallowed.' }
    $global:SocLogTest.FailBackup = $false
    $global:SocLogTest.Policies.Clear()
    $global:SocLogTest.FailSet = $true
    $failed = $false
    try { & $scriptPath }
    catch {
        if ($_.Exception.Message -notlike 'Failed to enable audit subcategory*') { throw }
        $failed = $true
    }
    if (!$failed) { throw 'auditpol set failure was swallowed.' }
    foreach ($path in $global:SocLogTest.TempFiles) {
        if (Test-Path -LiteralPath $path) { throw 'Temporary auditpol CSV export was not cleaned up.' }
    }
    Write-Output 'Windows service logging: IIS/AD config, idempotency, check mode, error handling, and cleanup verified (offline mock).'
}
finally {
    Remove-Variable -Name SocLogTest, Ansible -Scope Global
}
