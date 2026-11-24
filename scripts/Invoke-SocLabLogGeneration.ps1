#Requires -Version 5.1
<#
.SYNOPSIS
    Generates benign, marked security activity across SOC L2 lab resources to validate ingestion in Microsoft Sentinel.

.DESCRIPTION
    Executes the controlled tests documented in "docs/Sentinel-Coverage-and-Testing.md" using SOC-L2-Pxx-<RunId>
    markers. Uses zero exploits, never brute-forces real credentials, never reads sensitive passwords, and cleans up
    temporary artifacts (Kubernetes namespace and ARM tag). VMs are operated via "az vm run-command" and AKS via
    "az aks command invoke", requiring no local SSH, RDP, kubectl, or kubelogin.

    Tests by group:
      Windows    P02 failed logons with nonexistent accounts (4625), P03 marked process executions (4688),
                 P14 Application Warning event, P15 disposable domain account/group lifecycle
                 (4720/4722/4724/4725/4726/4727/4728/4729/4730/4732/4733/4738) plus failed logon on a disposable user.
      Linux      P04 logger across authpriv/auth/daemon/sudo, P04B failed SSH and su with nonexistent users (sshd/su),
                 P13 failed PostgreSQL login (local5).
      WebServers P11 HTTP requests to Apache (Syslog local6) and P12 to IIS (W3CIISLog).
      AppService P05 marked HTTPS probe requests (AppServiceHTTPLogs).
      KeyVault   P07 SecretList, SecretGet on linux-ssh-public-key (200), and SecretGet on a nonexistent secret (404).
      Arm        P09 merges and removes temporary tag SOCPrueba on the Linux VM (AzureActivity).
      Aks        P08 namespace/ConfigMap (AKSAuditAdmin), P10 non-privileged stdout pod (ContainerLogV2), and
                 P10E pod with nonexistent image tag (KubeEvents collects Warning events by default).
    P01 (Heartbeat) is queried only.

    Command-line arguments are recorded in cleartext in Event 4688 and Syslog; passwords used in P02/P13/P15 are
    synthetic invalid strings.

.EXAMPLE
    .\Invoke-SocLabLogGeneration.ps1 -WhatIf

.EXAMPLE
    .\Invoke-SocLabLogGeneration.ps1 -Test Windows, Linux -Verify

.EXAMPLE
    .\Invoke-SocLabLogGeneration.ps1 -VerifyOnly -RunId 20260101120000

.NOTES
    Invoked by Terraform from log_generation.tf at the end of deployment (enable_log_generation = true) with
    -WaitForSourcesMinutes and -InitialDelaySeconds so activity is generated only after sources start reporting.
#>
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Generate')]
param(
    [Parameter()]
    [string]$SubscriptionId,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ResourceGroup = 'soc-l2-rg',

    [Parameter(ParameterSetName = 'Generate')]
    [ValidateSet('All', 'Windows', 'Linux', 'WebServers', 'AppService', 'KeyVault', 'Arm', 'Aks')]
    [string[]]$Test = @('All'),

    [Parameter(ParameterSetName = 'Generate')]
    [Parameter(ParameterSetName = 'VerifyOnly', Mandatory)]
    [ValidatePattern('^[0-9]{14}$')]
    [string]$RunId = (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss'),

    [Parameter(ParameterSetName = 'Generate')]
    [ValidateRange(1, 5)]
    [int]$FailedLogonAttempts = 3,

    [Parameter(ParameterSetName = 'Generate')]
    [ValidateRange(0, 900)]
    [int]$ContainerLogWaitSeconds = 120,

    [Parameter(ParameterSetName = 'Generate')]
    [ValidateRange(0, 60)]
    [int]$WaitForSourcesMinutes = 0,

    [Parameter(ParameterSetName = 'Generate')]
    [ValidateRange(0, 1800)]
    [int]$InitialDelaySeconds = 0,

    [Parameter(ParameterSetName = 'Generate')]
    [switch]$Verify,

    [Parameter(ParameterSetName = 'VerifyOnly', Mandatory)]
    [switch]$VerifyOnly,

    [Parameter()]
    [ValidateRange(0, 60)]
    [int]$VerifyTimeoutMinutes = 20,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$StateDirectory = (Join-Path ([IO.Path]::GetTempPath()) 'soc-l2-loggen')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:TempFiles = New-Object System.Collections.Generic.List[string]
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Invoke-Az {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [switch]$AllowFailure,
        [switch]$Json
    )

    # az.cmd routes through cmd.exe: payloads containing quotes, |, or & are always passed via @file.
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & az @Arguments --only-show-errors 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
    }

    $stdout = (@($output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }) -join "`n").Trim()
    $stderr = (@($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) -join "`n").Trim()
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "az $($Arguments[0..([Math]::Min(2, $Arguments.Count - 1))] -join ' ') failed ($exitCode): $stderr"
    }

    $value = $stdout
    if ($Json -and $exitCode -eq 0 -and $stdout) { $value = $stdout | ConvertFrom-Json }
    [pscustomobject]@{ ExitCode = $exitCode; Value = $value; Error = $stderr }
}

function New-TempContentFile {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Content,
        [switch]$UnixLineEndings
    )

    $directory = Join-Path ([IO.Path]::GetTempPath()) "soc-l2-loggen-$RunId"
    if (-not (Test-Path -LiteralPath $directory)) { $null = New-Item -ItemType Directory -Path $directory }
    $path = Join-Path $directory $Name
    if ($UnixLineEndings) { $Content = $Content -replace "`r`n", "`n" }
    [IO.File]::WriteAllText($path, $Content, $script:Utf8NoBom)
    $script:TempFiles.Add($path)
    $path
}

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ("[{0:HH:mm:ss}Z] {1}" -f (Get-Date).ToUniversalTime(), $Message)
}

function Send-MarkedRequest {
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$UserAgent,
        [ValidateSet('GET', 'POST', 'PUT', 'DELETE', 'HEAD', 'OPTIONS')][string]$Method = 'GET'
    )

    try {
        $response = Invoke-WebRequest -Uri $Uri -UserAgent $UserAgent -Method $Method -UseBasicParsing -TimeoutSec 20 -MaximumRedirection 0
        [int]$response.StatusCode
    }
    catch {
        $response = $_.Exception.PSObject.Properties['Response']
        if ($response -and $response.Value) { return [int]$response.Value.StatusCode }
        throw "No HTTP response from ${Uri}: $($_.Exception.Message)"
    }
}

function Invoke-VmScript {
    param(
        [Parameter(Mandatory)][string]$VmName,
        [Parameter(Mandatory)][ValidateSet('Linux', 'Windows')][string]$OsType,
        [Parameter(Mandatory)][string]$Script
    )

    $commandId = if ($OsType -eq 'Linux') { 'RunShellScript' } else { 'RunPowerShellScript' }
    $extension = if ($OsType -eq 'Linux') { 'sh' } else { 'ps1' }
    $file = New-TempContentFile -Name "$VmName.$extension" -Content $Script -UnixLineEndings:($OsType -eq 'Linux')
    $result = Invoke-Az -Json -Arguments @(
        'vm', 'run-command', 'invoke', '--resource-group', $ResourceGroup, '--name', $VmName,
        '--command-id', $commandId, '--scripts', "@$file", '--output', 'json'
    )
    $message = (@($result.Value.value | ForEach-Object { $_.message }) -join "`n").Trim()
    if ($message -notmatch 'SOC-RESULT=OK') { throw "Execution on $VmName did not confirm success:`n$message" }
    $message
}

function Invoke-AksScript {
    param(
        [Parameter(Mandatory)][string]$ClusterName,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Script
    )

    $file = New-TempContentFile -Name $Name -Content $Script -UnixLineEndings
    $result = Invoke-Az -Json -Arguments @(
        'aks', 'command', 'invoke', '--resource-group', $ResourceGroup, '--name', $ClusterName,
        '--command', "sh $Name", '--file', $file, '--output', 'json'
    )
    $logs = [string]$result.Value.logs
    if ($result.Value.exitCode -ne 0 -or $logs -notmatch 'SOC-RESULT=OK') {
        throw "AKS command invoke returned exitCode $($result.Value.exitCode):`n$logs"
    }
    $logs
}

function Invoke-LabQuery {
    param(
        [Parameter(Mandatory)][string]$WorkspaceCustomerId,
        [Parameter(Mandatory)][string]$Query
    )

    $body = @{ query = $Query; timespan = 'P2D' } | ConvertTo-Json -Compress
    $file = New-TempContentFile -Name 'query.json' -Content $body
    $result = Invoke-Az -Json -Arguments @(
        'rest', '--method', 'post', '--url', "https://api.loganalytics.io/v1/workspaces/$WorkspaceCustomerId/query",
        '--resource', 'https://api.loganalytics.io', '--body', "@$file", '--output', 'json'
    )
    [int]$result.Value.tables[0].rows[0][0]
}

function Wait-LabSource {
    param(
        [Parameter(Mandatory)][string]$WorkspaceCustomerId,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Query,
        [Parameter(Mandatory)][int]$Expected,
        [Parameter(Mandatory)][datetime]$Deadline
    )

    do {
        $count = 0
        try { $count = Invoke-LabQuery -WorkspaceCustomerId $WorkspaceCustomerId -Query $Query }
        catch { Write-Warning "${Name}: $($_.Exception.Message)" }
        if ($count -ge $Expected) { Write-Step "$Name is reporting to the workspace."; return }
        if ((Get-Date) -ge $Deadline) { throw "$Name did not report to the workspace before timeout; aborting log generation." }
        Write-Step "Waiting for $Name to report to the workspace ($count/$Expected)."
        Start-Sleep -Seconds 60
    } while ($true)
}

function Get-LabCatalog {
    param(
        [Parameter(Mandatory)][string]$Run,
        [Parameter(Mandatory)][string]$StartUtc,
        [Parameter(Mandatory)][string]$Group
    )

    $since = "| where TimeGenerated >= datetime($StartUtc)"
    $namespace = "soc-l2-p08-$Run"
    $short = $Run.Substring(6)
    @(
        [pscustomobject]@{ Id = 'P01'; Group = 'Base'; Table = 'Heartbeat'; Query = @"
Heartbeat
| where TimeGenerated > ago(15m)
| summarize Latest = max(TimeGenerated) by Computer, Category, _ResourceId
"@ },
        [pscustomobject]@{ Id = 'P02'; Group = 'Windows'; Table = 'SecurityEvent'; Query = @"
SecurityEvent
$since
| where EventID == 4625 and TargetUserName startswith "soc-l2-p02"
| summarize Attempts = count() by TargetUserName, LogonType, Status, SubStatus, IpAddress
"@ },
        [pscustomobject]@{ Id = 'P15'; Group = 'Windows'; Table = 'SecurityEvent'; Query = @"
SecurityEvent
$since
| where EventID in (4720, 4722, 4723, 4724, 4725, 4726, 4727, 4728, 4729, 4730, 4732, 4733, 4738, 4767, 4776)
| where strcat(tostring(TargetUserName), tostring(MemberName), tostring(SubjectUserName), tostring(TargetAccount)) contains "$short"
| project TimeGenerated, EventID, Activity, SubjectUserName, TargetUserName, MemberName
"@ },
        [pscustomobject]@{ Id = 'P03'; Group = 'Windows'; Table = 'SecurityEvent'; Query = @"
SecurityEvent
$since
| where EventID == 4688 and CommandLine contains "SOC-L2-P03-$Run"
| project TimeGenerated, Computer, SubjectUserName, NewProcessName, CommandLine, ParentProcessName
"@ },
        [pscustomobject]@{ Id = 'P14'; Group = 'Windows'; Table = 'Event'; Query = @"
Event
$since
| where Source == "SOC-L2-Lab" and RenderedDescription contains "SOC-L2-P14-$Run"
| project TimeGenerated, Computer, EventLog, EventLevelName, EventID, RenderedDescription
"@ },
        [pscustomobject]@{ Id = 'P04'; Group = 'Linux'; Table = 'Syslog'; Query = @"
Syslog
$since
| where SyslogMessage contains "SOC-L2-P04-$Run"
| project TimeGenerated, Computer, Facility, SeverityLevel, ProcessName, SyslogMessage
"@ },
        [pscustomobject]@{ Id = 'P04B'; Group = 'Linux'; Table = 'Syslog (sshd)'; Query = @"
Syslog
$since
| where ProcessName in ("sshd", "su") and SyslogMessage contains "socp04$short"
| summarize Attempts = count() by ProcessName, SeverityLevel
"@ },
        [pscustomobject]@{ Id = 'P13'; Group = 'Linux'; Table = 'Syslog (local5)'; Query = @"
Syslog
$since
| where Facility == "local5" and SyslogMessage contains "soc_l2_p13_$Run"
| project TimeGenerated, Computer, ProcessName, SeverityLevel, SyslogMessage
"@ },
        [pscustomobject]@{ Id = 'P11'; Group = 'WebServers'; Table = 'Syslog (local6)'; Query = @"
Syslog
$since
| where Facility == "local6" and SyslogMessage contains "SOC-L2-P11-$Run"
| project TimeGenerated, Computer, ProcessName, SyslogMessage
"@ },
        [pscustomobject]@{ Id = 'P12'; Group = 'WebServers'; Table = 'W3CIISLog'; Query = @"
W3CIISLog
$since
| where csUriStem contains "SOC-L2-P12-$Run"
| project TimeGenerated, Computer, sSiteName, csMethod, csUriStem, scStatus, cIP, csUserAgent
"@ },
        [pscustomobject]@{ Id = 'P05'; Group = 'AppService'; Table = 'AppServiceHTTPLogs'; Query = @"
AppServiceHTTPLogs
$since
| where CsUriStem contains "SOC-L2-P05-$Run"
| project TimeGenerated, CsHost, CsMethod, CsUriStem, ScStatus, CIp, UserAgent
"@ },
        [pscustomobject]@{ Id = 'P07'; Group = 'KeyVault'; Table = 'AZKVAuditLogs'; Query = @"
AZKVAuditLogs
$since
| where OperationName =~ "SecretGet"
| where RequestUri contains "linux-ssh-public-key" or RequestUri contains "soc-l2-p07-$Run"
| project TimeGenerated, OperationName, HttpStatusCode, ResultType, CallerIpAddress, RequestUri
"@ },
        [pscustomobject]@{ Id = 'P09'; Group = 'Arm'; Table = 'AzureActivity'; Query = @"
AzureActivity
$since
| where ResourceGroup =~ "$ResourceGroup"
| where OperationNameValue startswith "MICROSOFT.RESOURCES/TAGS/"
| project TimeGenerated, OperationNameValue, ActivityStatusValue, Caller, CallerIpAddress, _ResourceId
"@ },
        [pscustomobject]@{ Id = 'P08'; Group = 'Aks'; Table = 'AKSAuditAdmin'; Query = @"
AKSAuditAdmin
$since
| where tostring(ObjectRef.namespace) == "$namespace" or tostring(ObjectRef.name) == "$namespace"
| extend ResourceKind = tostring(ObjectRef.resource), ObjectName = tostring(ObjectRef.name),
    Username = tostring(User.username), StatusCode = toint(ResponseStatus.code)
| project TimeGenerated, Verb, ResourceKind, ObjectName, Username, StatusCode, Stage
"@ },
        [pscustomobject]@{ Id = 'P10'; Group = 'Aks'; Table = 'ContainerLogV2'; Query = @"
ContainerLogV2
$since
| where PodNamespace == "$namespace" and tostring(LogMessage) contains "SOC-L2-P10-$Run"
| project TimeGenerated, Computer, PodNamespace, PodName, ContainerName, LogMessage
"@ },
        [pscustomobject]@{ Id = 'P10E'; Group = 'Aks'; Table = 'KubeEvents'; Query = @"
KubeEvents
$since
| where Namespace == "$namespace"
| project TimeGenerated, Name, ObjectKind, KubeEventType, Reason, Message
"@ }
    ) | Where-Object { $_.Group -eq 'Base' -or $Group -eq 'All' -or ($Group -split ',') -contains $_.Group }
}

function Invoke-Verification {
    param(
        [Parameter(Mandatory)]$State,
        [Parameter(Mandatory)][int]$TimeoutMinutes
    )

    $catalog = @(Get-LabCatalog -Run $State.RunId -StartUtc $State.StartUtc -Group $State.Groups)
    $pending = @($catalog | Where-Object { $State.Generated -contains $_.Id -or $_.Id -eq 'P01' })
    $found = @{}
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    do {
        foreach ($item in @($pending | Where-Object { -not $found.ContainsKey($_.Id) })) {
            try {
                $count = Invoke-LabQuery -WorkspaceCustomerId $State.WorkspaceCustomerId -Query "$($item.Query)`n| count"
                if ($count -gt 0) { $found[$item.Id] = $count; Write-Step "$($item.Id) visible in $($item.Table): $count row(s)." }
            }
            catch { Write-Warning "$($item.Id): $($_.Exception.Message)" }
        }
        $missing = @($pending | Where-Object { -not $found.ContainsKey($_.Id) })
        if ($missing.Count -eq 0 -or (Get-Date) -ge $deadline) { break }
        Write-Step "Waiting for ingestion of: $($missing.Id -join ', ') (typical latency is 2 to 15 minutes)."
        Start-Sleep -Seconds 60
    } while ($true)

    $pending | ForEach-Object {
        [pscustomobject]@{
            Test   = $_.Id
            Table  = $_.Table
            Rows   = if ($found.ContainsKey($_.Id)) { $found[$_.Id] } else { 0 }
            Status = if ($found.ContainsKey($_.Id)) { 'Visible' } else { 'Pending' }
        }
    }
}

try {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'Azure CLI (az) is not installed or not in PATH.' }
    if ($SubscriptionId) { $null = Invoke-Az -Arguments @('account', 'set', '--subscription', $SubscriptionId) }
    $account = (Invoke-Az -Json -Arguments @('account', 'show', '--output', 'json')).Value
    Write-Step "Subscription $($account.id) as $($account.user.name); RunId $RunId."

    if (-not (Test-Path -LiteralPath $StateDirectory)) { $null = New-Item -ItemType Directory -Path $StateDirectory }
    $statePath = Join-Path $StateDirectory "$RunId.json"

    if ($VerifyOnly) {
        if (-not (Test-Path -LiteralPath $statePath)) { throw "State file $statePath does not exist for RunId $RunId." }
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        Invoke-Verification -State $state -TimeoutMinutes $VerifyTimeoutMinutes | Format-Table -AutoSize
        return
    }

    $groups = if ($Test -contains 'All') { 'All' } else { ($Test | Select-Object -Unique) -join ',' }
    $selected = { param($name) $groups -eq 'All' -or ($groups -split ',') -contains $name }

    Write-Step "Discovering resources in $ResourceGroup."
    $vms = @((Invoke-Az -Json -Arguments @('vm', 'list', '--resource-group', $ResourceGroup, '--show-details', '--output', 'json')).Value)
    $linuxVm = $vms | Where-Object { $_.storageProfile.osDisk.osType -eq 'Linux' } | Select-Object -First 1
    $windowsVm = $vms | Where-Object { $_.storageProfile.osDisk.osType -eq 'Windows' } | Select-Object -First 1
    $webApp = @((Invoke-Az -Json -Arguments @('webapp', 'list', '--resource-group', $ResourceGroup, '--output', 'json')).Value) | Select-Object -First 1
    $keyVault = @((Invoke-Az -Json -Arguments @('keyvault', 'list', '--resource-group', $ResourceGroup, '--output', 'json')).Value) | Select-Object -First 1
    $aks = @((Invoke-Az -Json -Arguments @('aks', 'list', '--resource-group', $ResourceGroup, '--output', 'json')).Value) | Select-Object -First 1
    $workspace = @((Invoke-Az -Json -Arguments @('monitor', 'log-analytics', 'workspace', 'list', '--resource-group', $ResourceGroup, '--output', 'json')).Value) | Select-Object -First 1
    if (-not $workspace) { throw "No Log Analytics workspace found in $ResourceGroup." }

    if ($WaitForSourcesMinutes -gt 0 -and -not $WhatIfPreference) {
        # Newly created resources: AMA and Container Insights take several minutes to send their first records.
        $deadline = (Get-Date).AddMinutes($WaitForSourcesMinutes)
        $vmIds = @(@($linuxVm, $windowsVm) | Where-Object { $_ } | ForEach-Object { '"{0}"' -f $_.id.ToLowerInvariant() })
        if ($vmIds.Count -gt 0) {
            Wait-LabSource -WorkspaceCustomerId $workspace.customerId -Name 'VM AMA (Heartbeat)' -Expected $vmIds.Count -Deadline $deadline -Query @"
Heartbeat
| where TimeGenerated > ago(15m)
| where tolower(_ResourceId) in ($($vmIds -join ', '))
| summarize dcount(tolower(_ResourceId))
"@
        }
        if ($aks -and (& $selected 'Aks')) {
            Wait-LabSource -WorkspaceCustomerId $workspace.customerId -Name 'AKS Container Insights (KubePodInventory)' -Expected 1 -Deadline $deadline -Query @"
KubePodInventory
| where TimeGenerated > ago(15m)
| where ClusterName =~ "$($aks.name)"
| count
"@
        }
    }
    if ($InitialDelaySeconds -gt 0 -and -not $WhatIfPreference) {
        Write-Step "Waiting $InitialDelaySeconds s for newly created diagnostic settings to begin exporting."
        Start-Sleep -Seconds $InitialDelaySeconds
    }

    $state = [ordered]@{
        RunId               = $RunId
        StartUtc            = (Get-Date).ToUniversalTime().AddMinutes(-1).ToString('yyyy-MM-ddTHH:mm:ssZ')
        Groups              = $groups
        WorkspaceCustomerId = $workspace.customerId
        Generated           = @()
    }
    $results = New-Object System.Collections.Generic.List[object]

    $runTest = {
        param([string]$Group, [string[]]$Ids, [object]$Resource, [string]$ResourceLabel, [scriptblock]$Action)
        if (-not (& $selected $Group)) { return }
        if (-not $Resource) {
            $results.Add([pscustomobject]@{ Group = $Group; Tests = $Ids -join ','; Status = 'Skipped'; Detail = "$ResourceLabel not found." })
            return
        }
        if (-not $PSCmdlet.ShouldProcess($ResourceLabel, "Generate activity $($Ids -join ', ')")) {
            $results.Add([pscustomobject]@{ Group = $Group; Tests = $Ids -join ','; Status = 'WhatIf'; Detail = $ResourceLabel })
            return
        }
        try {
            Write-Step "$Group ($($Ids -join ', ')) on $ResourceLabel."
            $detail = & $Action
            $state.Generated += $Ids
            $results.Add([pscustomobject]@{ Group = $Group; Tests = $Ids -join ','; Status = 'Generated'; Detail = [string]$detail })
        }
        catch {
            Write-Warning "$Group failed: $($_.Exception.Message)"
            $results.Add([pscustomobject]@{ Group = $Group; Tests = $Ids -join ','; Status = 'Error'; Detail = $_.Exception.Message })
        }
    }

    & $runTest 'Windows' @('P02', 'P03', 'P14', 'P15') $windowsVm "VM $($windowsVm.name)" {
        $windowsScript = @'
$ErrorActionPreference = 'Continue'
$run = '__RUN__'
$short = '__SHORT__'

# --- P02: varied logon failures with nonexistent accounts (4625) ---
$ghosts = @("soc-l2-p02-nonexistent", "soc-l2-p02-ghost-$short", "soc-l2-p02-svc-$short", "soc-l2-p02-admin-$short")
for ($i = 1; $i -le __ATTEMPTS__; $i++) {
    foreach ($g in $ghosts) { $null = & net.exe use \\127.0.0.1\IPC$ "SOC-L2-P02-invalid" /user:$g 2>&1 }
}

# --- P03: marked process creation (4688) ---
$null = & cmd.exe /c "echo SOC-L2-P03-$run"
$null = & whoami.exe /priv
$null = & powershell.exe -NoProfile -Command "Write-Output 'SOC-L2-P03-$run-ps'; Get-Process | Out-Null"

# --- P14: Application Warning event (Event) ---
$null = & eventcreate.exe /T WARNING /ID 900 /L APPLICATION /SO SOC-L2-Lab /D "SOC-L2-P14-$run benign Event ingestion test" 2>&1
if ($LASTEXITCODE -ne 0) { Write-Output "eventcreate returned $LASTEXITCODE"; exit 1 }

# --- P15: disposable AD domain user and group lifecycle (account management) ---
Import-Module ActiveDirectory -ErrorAction Stop
$u1 = "SOCp15a$short"
$u2 = "SOCp15b$short"
$grp = "SOCg15$short"
$domain = (Get-ADDomain -Server localhost)
$dnsRoot = $domain.DNSRoot
$netbios = $domain.NetBIOSName
$pw1 = ConvertTo-SecureString "Soc!L2a-$short-Aa" -AsPlainText -Force
$pw2 = ConvertTo-SecureString "Soc!L2b-$short-Bb" -AsPlainText -Force
$pwReset = ConvertTo-SecureString "Soc!L2r-$short-Cc" -AsPlainText -Force
try {
    New-ADUser -Server localhost -Name $u1 -SamAccountName $u1 -AccountPassword $pw1 -Enabled $true -Description "SOC-L2-P15-$run disposable" -ErrorAction Stop   # 4720/4722/4724
    New-ADUser -Server localhost -Name $u2 -SamAccountName $u2 -AccountPassword $pw2 -Enabled $false -Description "SOC-L2-P15-$run disposable" -ErrorAction Stop  # 4720
    Set-ADAccountPassword -Server localhost -Identity $u1 -Reset -NewPassword $pwReset -ErrorAction Stop                                                          # 4724
    Set-ADUser -Server localhost -Identity $u1 -Description "SOC-L2-P15-$run modified" -ErrorAction Stop                                                          # 4738
    New-ADGroup -Server localhost -Name $grp -SamAccountName $grp -GroupScope Global -GroupCategory Security -Description "SOC-L2-P15-$run" -ErrorAction Stop     # 4727
    Add-ADGroupMember -Server localhost -Identity $grp -Members $u1, $u2 -ErrorAction Stop                                                                        # 4728
    Remove-ADGroupMember -Server localhost -Identity $grp -Members $u2 -Confirm:$false -ErrorAction Stop                                                          # 4729
    Add-ADGroupMember -Server localhost -Identity "Guests" -Members $u2 -ErrorAction Stop                                                                         # 4732 (domain local group)
    Remove-ADGroupMember -Server localhost -Identity "Guests" -Members $u2 -Confirm:$false -ErrorAction Stop                                                      # 4733
    Enable-ADAccount -Server localhost -Identity $u2 -ErrorAction Stop                                                                                            # 4722
    Disable-ADAccount -Server localhost -Identity $u1 -ErrorAction Stop                                                                                           # 4725

    # Failed authentication against a valid disposable domain account (4625 + 4771/4776)
    for ($i = 1; $i -le __ATTEMPTS__; $i++) {
        $null = & net.exe use "\\$dnsRoot\IPC$" "WrongPass-$short" /user:"$netbios\$u2" 2>&1
    }
    Write-Output "SOC-P15=generated u1=$u1 u2=$u2 group=$grp domain=$dnsRoot"
}
finally {
    Remove-ADGroup -Server localhost -Identity $grp -Confirm:$false -ErrorAction SilentlyContinue   # 4730
    Remove-ADUser -Server localhost -Identity $u1 -Confirm:$false -ErrorAction SilentlyContinue      # 4726
    Remove-ADUser -Server localhost -Identity $u2 -Confirm:$false -ErrorAction SilentlyContinue      # 4726
}
Write-Output 'SOC-RESULT=OK'
'@
        $windowsScript = $windowsScript.Replace('__RUN__', $RunId).Replace('__SHORT__', $RunId.Substring(6)).Replace('__ATTEMPTS__', [string]$FailedLogonAttempts)
        $output = Invoke-VmScript -VmName $windowsVm.name -OsType Windows -Script $windowsScript
        ($output -split "`n" | Where-Object { $_ -match 'SOC-P15' }) -join ' '
    }

    & $runTest 'Linux' @('P04', 'P04B', 'P13') $linuxVm "VM $($linuxVm.name)" {
        $linuxScript = @'
#!/bin/bash
set -u
RUN='__RUN__'
SHORT='__SHORT__'
# --- P04: markers across multiple Syslog facilities/severities ---
logger -p authpriv.notice -t soc-lab "SOC-L2-P04-${RUN} benign authpriv test"
logger -p auth.warning -t soc-lab "SOC-L2-P04-${RUN} benign auth test"
logger -p daemon.warning -t soc-lab "SOC-L2-P04-${RUN} benign daemon test"
logger -p authpriv.warning -t sudo "SOC-L2-P04-${RUN} benign sudo marker"
# --- P04B: failed SSH authentication with nonexistent users (sshd Invalid user) ---
for n in 1 2 3 4 5; do
  timeout 15 ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 "socp04${SHORT}u${n}@127.0.0.1" true >/dev/null 2>&1 || true
done
# su to a nonexistent user (authpriv FAILED SU)
timeout 15 su - "socp04${SHORT}su" -c true >/dev/null 2>&1 || true
# --- P13: failed PostgreSQL login (local5) ---
if command -v psql >/dev/null 2>&1; then
  PGPASSWORD='SOC-L2-P13-invalid' PGCONNECT_TIMEOUT=5 psql "host=127.0.0.1 dbname=postgres user=soc_l2_p13_${RUN} application_name=SOC-L2-P13-${RUN}" -c 'SELECT 1' >/dev/null 2>&1 || true
  echo "SOC-P13=generated"
else
  echo "SOC-P13=skipped, psql not installed"
fi
echo 'SOC-RESULT=OK'
'@
        $linuxScript = $linuxScript.Replace('__RUN__', $RunId).Replace('__SHORT__', $RunId.Substring(6))
        $output = Invoke-VmScript -VmName $linuxVm.name -OsType Linux -Script $linuxScript
        ($output -split "`n" | Where-Object { $_ -match 'SOC-P13' }) -join ' '
    }

    $webServers = if ($linuxVm -and $windowsVm -and $linuxVm.publicIps -and $windowsVm.publicIps) { $true } else { $null }
    & $runTest 'WebServers' @('P11', 'P12') $webServers 'Apache and IIS (HTTP 80)' {
        $agent = "SOC-L2-Lab/$RunId"
        $apache = Send-MarkedRequest -Uri "http://$($linuxVm.publicIps)/SOC-L2-P11-$RunId" -UserAgent $agent
        $iis = Send-MarkedRequest -Uri "http://$($windowsVm.publicIps)/SOC-L2-P12-$RunId" -UserAgent $agent
        "Apache HTTP $apache; IIS HTTP $iis"
    }

    & $runTest 'AppService' @('P05') $webApp "App Service $($webApp.name)" {
        $agent = "SOC-L2-Lab/$RunId"
        $paths = @(
            "SOC-L2-P05-$RunId",
            "SOC-L2-P05-$RunId/admin",
            "SOC-L2-P05-$RunId/.env",
            "SOC-L2-P05-$RunId/wp-login.php",
            "SOC-L2-P05-$RunId/../etc/passwd",
            "SOC-L2-P05-$RunId/api/v1/users?id=1' OR '1'='1"
        )
        $codes = foreach ($path in $paths) {
            Send-MarkedRequest -Uri "https://$($webApp.defaultHostName)/$path" -UserAgent $agent
        }
        foreach ($method in @('POST', 'PUT', 'DELETE')) {
            $codes += Send-MarkedRequest -Uri "https://$($webApp.defaultHostName)/SOC-L2-P05-$RunId/$method" -UserAgent $agent -Method $method
        }
        "HTTPS $($codes -join ', ')"
    }

    & $runTest 'KeyVault' @('P07') $keyVault "Key Vault $($keyVault.name)" {
        $secrets = @((Invoke-Az -Json -Arguments @('keyvault', 'secret', 'list', '--vault-name', $keyVault.name, '--output', 'json')).Value)
        $secret = $secrets | Where-Object { $_.name -eq 'linux-ssh-public-key' } | Select-Object -First 1
        if ($secret) {
            $null = Invoke-Az -Arguments @('keyvault', 'secret', 'show', '--id', $secret.id, '--query', 'id', '--output', 'tsv')
        }
        else {
            Write-Step 'P07: linux-ssh-public-key not present; generating SecretList and failed SecretGet without reading passwords.'
        }
        $missing = Invoke-Az -AllowFailure -Arguments @('keyvault', 'secret', 'show', '--vault-name', $keyVault.name, '--name', "soc-l2-p07-$RunId-nonexistent", '--query', 'id', '--output', 'tsv')
        if ($missing.ExitCode -eq 0) { throw 'Nonexistent P07 secret unexpectedly succeeded; verify secret names.' }
        'SecretList, SecretGet on linux-ssh-public-key if present, and failed SecretGet on nonexistent secret'
    }

    & $runTest 'Arm' @('P09') $linuxVm "Temporary tag on VM $($linuxVm.name)" {
        $tagsResult = Invoke-Az -Json -Arguments @('resource', 'show', '--ids', $linuxVm.id, '--query', 'tags', '--output', 'json')
        $previousTag = if ($tagsResult.Value -and $tagsResult.Value.PSObject.Properties['SOCPrueba']) { [string]$tagsResult.Value.SOCPrueba } else { $null }
        try {
            $null = Invoke-Az -Arguments @('tag', 'update', '--resource-id', $linuxVm.id, '--operation', 'Merge', '--tags', "SOCPrueba=SOC-L2-P09-$RunId", '--output', 'none')
            Start-Sleep -Seconds 5
        }
        finally {
            if ($previousTag) {
                $null = Invoke-Az -Arguments @('tag', 'update', '--resource-id', $linuxVm.id, '--operation', 'Merge', '--tags', "SOCPrueba=$previousTag", '--output', 'none')
            }
            else {
                $null = Invoke-Az -Arguments @('tag', 'update', '--resource-id', $linuxVm.id, '--operation', 'Delete', '--tags', "SOCPrueba=SOC-L2-P09-$RunId", '--output', 'none')
            }
        }
        'Tag SOCPrueba added and restored'
    }

    & $runTest 'Aks' @('P08', 'P10', 'P10E') $aks "AKS $($aks.name)" {
        $namespace = "soc-l2-p08-$RunId"
        $generateScript = @'
set -eu
NS='__NS__'
if kubectl get namespace "$NS" >/dev/null 2>&1; then echo "Namespace $NS already exists; aborting test."; exit 3; fi
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Namespace
metadata:
  name: __NS__
  labels:
    soc-lab: "true"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: soc-l2-p08
  namespace: __NS__
data:
  marker: SOC-L2-P08-__RUN__
---
apiVersion: v1
kind: Pod
metadata:
  name: soc-l2-p10
  namespace: __NS__
  labels:
    app: soc-l2-p10
spec:
  restartPolicy: Never
  automountServiceAccountToken: false
  securityContext:
    runAsNonRoot: true
    runAsUser: 65534
    runAsGroup: 65534
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: marker
      image: mcr.microsoft.com/azurelinux/busybox:1.36
      command: ["/bin/sh", "-c"]
      args:
        - 'for i in 1 2 3 4 5 6; do echo "SOC-L2-P10-__RUN__ line $i"; sleep 10; done'
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: ["ALL"]
      resources:
        requests:
          cpu: 10m
          memory: 16Mi
        limits:
          cpu: 50m
          memory: 32Mi
---
# Nonexistent image tag: produces Warning events (ErrImagePull), which Container Insights exports to KubeEvents by default.
apiVersion: v1
kind: Pod
metadata:
  name: soc-l2-p10e
  namespace: __NS__
spec:
  restartPolicy: Never
  automountServiceAccountToken: false
  securityContext:
    runAsNonRoot: true
    runAsUser: 65534
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: missing-image
      image: mcr.microsoft.com/azurelinux/busybox:soc-l2-p10e-nonexistent
      securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
      resources:
        limits:
          cpu: 10m
          memory: 16Mi
EOF
kubectl wait --namespace "$NS" --for=jsonpath='{.status.phase}'=Succeeded pod/soc-l2-p10 --timeout=180s
kubectl logs --namespace "$NS" soc-l2-p10 | tail -n 2
echo 'SOC-RESULT=OK'
'@
        $cleanupScript = @'
NS='__NS__'
kubectl delete configmap soc-l2-p08 --namespace "$NS" --ignore-not-found
kubectl delete pod soc-l2-p10 soc-l2-p10e --namespace "$NS" --ignore-not-found --wait=false
kubectl delete namespace "$NS" --ignore-not-found --wait=false
echo 'SOC-RESULT=OK'
'@
        try {
            $null = Invoke-AksScript -ClusterName $aks.name -Name 'soc-l2-aks-generate.sh' -Script $generateScript.Replace('__NS__', $namespace).Replace('__RUN__', $RunId)
            Write-Step "Pod completed; waiting $ContainerLogWaitSeconds s for AMA to collect ContainerLogV2 before cleanup."
            Start-Sleep -Seconds $ContainerLogWaitSeconds
        }
        finally {
            Write-Step "Cleaning up namespace $namespace."
            $null = Invoke-AksScript -ClusterName $aks.name -Name 'soc-l2-aks-cleanup.sh' -Script $cleanupScript.Replace('__NS__', $namespace)
        }
        "Namespace $namespace created and deleted"
    }

    $state.EndUtc = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $results | Format-Table -AutoSize -Wrap

    if ($WhatIfPreference) { return }

    $state | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $statePath -Encoding UTF8
    $catalog = @(Get-LabCatalog -Run $RunId -StartUtc $state.StartUtc -Group $groups | Where-Object { $state.Generated -contains $_.Id -or $_.Id -eq 'P01' })
    $kqlPath = Join-Path $StateDirectory "$RunId-queries.kql"
    ($catalog | ForEach-Object { "// $($_.Id) - $($_.Table)`n$($_.Query)`n" }) -join "`n" | Set-Content -LiteralPath $kqlPath -Encoding UTF8
    Write-Step "State saved: $statePath"
    Write-Step "KQL queries for Sentinel > Logs: $kqlPath"

    if ($Verify) { Invoke-Verification -State ([pscustomobject]$state) -TimeoutMinutes $VerifyTimeoutMinutes | Format-Table -AutoSize }
    else { Write-Step "To verify later: .\Invoke-SocLabLogGeneration.ps1 -VerifyOnly -RunId $RunId" }

    if (@($results | Where-Object Status -eq 'Error').Count -gt 0) { exit 1 }
    exit 0
}
finally {
    foreach ($file in $script:TempFiles) { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
    $tempDirectory = Join-Path ([IO.Path]::GetTempPath()) "soc-l2-loggen-$RunId"
    if (Test-Path -LiteralPath $tempDirectory) { Remove-Item -LiteralPath $tempDirectory -Recurse -Force -ErrorAction SilentlyContinue }
}
