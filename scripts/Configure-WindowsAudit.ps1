$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Los GUID evitan depender del idioma del sistema: Logon y Process Creation.
& auditpol.exe /set '/subcategory:{0CCE9215-69AE-11D9-BED3-505054503030},{0CCE922B-69AE-11D9-BED3-505054503030}' /success:enable /failure:enable
if ($LASTEXITCODE -ne 0) {
    throw "auditpol no pudo habilitar la auditoria. Codigo: $LASTEXITCODE"
}

$lsaPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
New-ItemProperty -Path $lsaPath -Name SCENoApplyLegacyAuditPolicy -Value 1 -PropertyType DWord -Force | Out-Null

$auditPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit'
if (-not (Test-Path -LiteralPath $auditPath)) {
    New-Item -Path $auditPath | Out-Null
}
New-ItemProperty -Path $auditPath -Name ProcessCreationIncludeCmdLine_Enabled -Value 1 -PropertyType DWord -Force | Out-Null

if ((Get-ItemPropertyValue -Path $lsaPath -Name SCENoApplyLegacyAuditPolicy) -ne 1 -or
    (Get-ItemPropertyValue -Path $auditPath -Name ProcessCreationIncludeCmdLine_Enabled) -ne 1) {
    throw 'La verificacion de las politicas de auditoria Windows fallo.'
}

Write-Output 'Auditoria de logon y procesos configurada; 4688 incluira argumentos en texto plano. No usar secretos en argumentos.'
