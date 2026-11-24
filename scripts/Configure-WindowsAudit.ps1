$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Subcategory GUIDs avoid OS display-language dependencies: Logon and Process Creation.
& auditpol.exe /set '/subcategory:{0CCE9215-69AE-11D9-BED3-505054503030},{0CCE922B-69AE-11D9-BED3-505054503030}' /success:enable /failure:enable
if ($LASTEXITCODE -ne 0) {
    throw "auditpol failed to enable auditing. Exit code: $LASTEXITCODE"
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
    throw 'Windows audit policy registry verification failed.'
}

Write-Output 'Logon and Process Creation auditing configured; Event 4688 will include cleartext command-line arguments. Do not pass secrets in arguments.'
