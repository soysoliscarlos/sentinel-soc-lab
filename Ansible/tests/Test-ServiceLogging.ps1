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
    # Como IIS real: enums/cadenas sin envoltorio; booleanos dentro de ConfigurationAttribute.
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
        # Encabezados localizados: solo el GUID y el valor numerico son estables.
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
                Equipo = 'LAB'
                Objetivo = 'Sistema'
                Subcategoria = 'Localizada'
                Identificador = $guid
                Inclusion = 'Exito y error'
                Exclusion = ''
                Valor = [int]$global:SocLogTest.Policies[$guid]
            }
        }
        $rows | Export-Csv -LiteralPath $path -NoTypeInformation
    }
    elseif ($args[0] -eq '/set') {
        if ($global:SocLogTest.FailSet) { $global:LASTEXITCODE = 1; return }
        $global:SocLogTest.Policies[$args[1].Substring('/subcategory:'.Length)] = 3
        $global:SocLogTest.Writes++
    }
    else { throw 'Operacion auditpol inesperada.' }
}

try {
    & $scriptPath
    if (!$global:Ansible.Changed -or $global:SocLogTest.Writes -ne 16) {
        throw 'No se configuraron seis propiedades IIS, siete politicas y tres canales.'
    }
    if ($global:SocLogTest.Iis.logFormat -ne 'W3C' -or
        $global:SocLogTest.Iis.period -ne 'Hourly' -or
        $global:SocLogTest.Iis.directory -ne 'C:\inetpub\logs\LogFiles') {
        throw 'La configuracion IIS no coincide con la fuente DCR.'
    }
    $global:SocLogTest.Writes = 0
    & $scriptPath
    if ($global:Ansible.Changed -or $global:SocLogTest.Writes -ne 0) {
        throw 'La configuracion de logs no es idempotente.'
    }
    $global:SocLogTest.Iis.period = 'Daily'
    $global:Ansible.CheckMode = $true
    & $scriptPath
    if (!$global:Ansible.Changed -or $global:SocLogTest.Writes -ne 0) {
        throw 'Check mode debe detectar cambios sin escribir.'
    }
    $global:Ansible.CheckMode = $false
    $global:SocLogTest.FailBackup = $true
    $failed = $false
    try { & $scriptPath }
    catch {
        if ($_.Exception.Message -notlike 'No se pudo consultar*') { throw }
        $failed = $true
    }
    if (!$failed) { throw 'Se oculto un fallo de lectura de auditpol.' }
    $global:SocLogTest.FailBackup = $false
    $global:SocLogTest.Policies.Clear()
    $global:SocLogTest.FailSet = $true
    $failed = $false
    try { & $scriptPath }
    catch {
        if ($_.Exception.Message -notlike 'No se pudo activar la auditoria*') { throw }
        $failed = $true
    }
    if (!$failed) { throw 'Se oculto un fallo de escritura de auditpol.' }
    foreach ($path in $global:SocLogTest.TempFiles) {
        if (Test-Path -LiteralPath $path) { throw 'No se limpio el CSV temporal de auditoria.' }
    }
    Write-Output 'Logs Windows: configuracion IIS/AD, idempotencia, check mode, errores y limpieza correctos con dobles locales.'
}
finally {
    Remove-Variable -Name SocLogTest, Ansible -Scope Global
}
