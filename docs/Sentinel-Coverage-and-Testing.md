**English** | [Español](Sentinel-Coverage-and-Testing.es.md)

# Microsoft Sentinel: Coverage and Controlled Testing for the SOC L2 Lab

Date: 2026-10-22.

**Configuration update (2026-10-22):** [Ansible invoked by Terraform](../Ansible/README.md) was prepared without running it against live VMs: IIS and AD forest `lab.example.test` on Windows; Apache and PostgreSQL on Ubuntu. `enable_ansible` is enabled in the lab inputs (`false` by default). After installing and verifying services, their logs are configured and existing DCRs are expanded: IIS to `W3CIISLog`; AD accounts/Kerberos/NTLM to `SecurityEvent`; Directory Service/DNS/DFS errors and warnings to `Event`; Apache `local6` and PostgreSQL `local5` to `Syslog`. `log_statement='all'` was explicitly authorized: it may record secrets and increase ingestion costs. Verification queries and limits are documented in the linked Ansible guide.

**Status:** proposed procedures. A read-only live review queried Azure and confirmed ingestion from the core resources. Live evidence and limitations are documented in [Live Verification of Connections and Ingestion](../README.md#live-verification-of-connections-and-ingestion); incident tables in section 7 include illustrative designs alongside opt-in Terraform rules.

**Scope change:** Application Gateway/WAF was removed from the codebase by user decision. Test P05 now targets App Service directly over HTTPS; P06 is retained strictly as a disabled historical reference, not as an active test. Do not recreate WAF resources to run this guide without separate approval.

## 1. What Monitoring All Resources Means

Enabling Sentinel on a workspace does not automatically discover or ingest all activity. Four layers must be wired together:

1. **Control plane:** resource creation/changes, network security rules, diagnostic settings, and RBAC changes via `AzureActivity`.
2. **Data plane and guest OS:** secret access, HTTP requests, process execution, authentication, and Kubernetes API/workload operations via diagnostic settings and AMA/DCR.
3. **Detection:** scheduled analytic rules that turn raw log events into alerts and incidents; raw logs alone never create incidents.
4. **Coverage:** inventory of expected log sources, last-seen timestamps, ingestion volume, and connector/rule health.

Resources like public IPs, NICs, disks, or Private Endpoints do not necessarily emit per-packet security logs on their own. Their visibility comes from Activity Log, Azure Monitor metrics/health, and telemetry from the attached compute or PaaS services. Sentinel serves as the SIEM; availability, latency, and infrastructure metrics belong in Azure Monitor.

Local files reviewed: [deployment scope](../README.md), [data collection](../monitoring.tf), [VMs and AMA](../compute.tf), and [Key Vault](../key_vault.tf).

## 2. Defined Coverage and Optional Enhancements

"Defined" means declared in Terraform; check the live verification section to distinguish already-deployed resources from pending changes.

| Resource or Layer | Currently Defined | Expected Table | Proposed Enhancement & Limitation |
| --- | --- | --- | --- |
| Subscription & lab RG | Eight-category Activity Log diagnostic setting | `AzureActivity` | Detect NSG, RBAC, and diagnostic changes. Filter by resource group or ID: subscription-scoped diagnostics include other resources in the same subscription. |
| Ubuntu VM | AMA, managed identity, `rsyslog`, and DCR (`auth`/`authpriv`/`daemon`/`syslog`/`kern`) | `Syslog`, `Heartbeat` | Detect SSH failures and `sudo` usage. Add `auditd` with a validated ingestion path if process/file auditing is required: `Syslog` is not full syscall auditing. SSH uses key auth; never enable password auth just for testing. |
| Windows VM | AMA and DCR with selected Security Event IDs and System/Application errors & warnings; logon/process audit extension prepared | `SecurityEvent`, `Event`, `Heartbeat` | Ingestion verified. The prepared extension enables 4688 command-line arguments. Additional account policies outside those subcategories require Ansible (`enable_ansible`). |
| IIS, AD DS & DNS on Windows | Prepared in Ansible and DCR: hourly IIS W3C, accounts/groups/computers, Kerberos/NTLM, Directory Service Changes, and service channels | `W3CIISLog`, `SecurityEvent`, `Event` | Distinct from App Service. Object SACLs are not created automatically (5136+ require SACLs). LDAP/DNS debug logs and Failed Request Tracing are not enabled. |
| Apache & PostgreSQL on Ubuntu | Prepared in Ansible and DCR: `rsyslog` `imfile` for Apache access/error (`local6`); PostgreSQL native Syslog (`local5`), connections, errors, and full SQL | `Syslog` | Filter by `ProcessName` (`apache-access`, `apache-error`, `postgres-soc`) and `_ResourceId`. Not `pgAudit`. Long SQL statements may fragment across rows. |
| PowerShell & Sysmon | Not implemented | `Event`, `WindowsEvent`, or custom table | PowerShell Script Block Logging (4104) requires enabling policy and collecting `Microsoft-Windows-PowerShell/Operational`. Sysmon requires installation, XML config, and its own DCR stream. |
| App Service Linux B1 | HTTP, console, publish audit, IP security audit, and platform diagnostics | `AppServiceHTTPLogs`, `AppServiceConsoleLogs`, `AppServiceAuditLogs`, `AppServiceIPSecAuditLogs`, `AppServicePlatformLogs` | Deploy an approved sample app if application-level logs are desired. Add Application Insights for distributed tracing/exceptions. |
| Application Gateway/WAF | Removed from codebase; no Gateway deployed | No WAF telemetry expected | Residual WAF policy without Gateway provides no active filtering; untouched. |
| AKS | Container Insights (three streams) + admin audit / control plane diagnostics + `guard` | `ContainerLogV2`, `KubeEvents`, `KubePodInventory`, `AKSAuditAdmin`, `AKSControlPlane` | `ContainerLogV2` excludes `kube-system` stdout/stderr by default unless configured; user namespaces emit logs normally. `kube-audit-admin` excludes `get`/`list` reads; switching to full `kube-audit` requires cost review. |
| Key Vault | `AuditEvent`, `Dedicated` destination, Private Endpoint + restricted public firewall | `AZKVAuditLogs` | Alert on `403`/`404` anomalies and unexpected secret reads. Private Endpoint does not replace RBAC or audit logging. |
| VNet, NSG, NIC, IP, routes & Private Endpoint | ARM control-plane changes in Activity Log; no network flow logs | `AzureActivity` | Add VNet flow logs + Storage + Traffic Analytics if approved. Raw flow logs go to Storage first, not directly into Sentinel. |
| Disks, App Service plan, LB & AKS managed `MC_` RG | ARM control-plane changes in Activity Log; metrics in Azure Monitor | `AzureActivity` | Include the `MC_` resource group in asset inventories. Never manually install AMA on AKS-managed VMSS nodes. |
| Entra ID (Tenant) | No connector configured | `SigninLogs`, `AuditLogs`, etc. | Connect Entra ID if tenant identity visibility is approved. Requires tenant roles/licenses and covers the entire tenant, not just the lab RG. |
| Microsoft Defender | Optional Defender for Servers (P1/P2) and MDE via `enable_defender_for_servers` | `SecurityAlert`, `SecurityIncident` | Evaluate Defender for Containers, App Service, and Key Vault based on budget. Avoid duplicate alert connectors when XDR integration is active. |
| Microsoft Sentinel | Dedicated onboarding on shared workspace + opt-in `LAB-Pxx` rules, workbook, playbooks, and notebooks | All tables above + `SecurityAlert` / `SecurityIncident` | Enable **Auditing and health monitoring** (`SentinelHealth`, `SentinelAudit`) in Sentinel Settings if operational health tracking is desired. |

**Networking note:** for new flow-log deployments, use **VNet flow logs**. Do not propose new NSG flow logs (creation blocked since 2025-06-30; retirement scheduled for 2027-09-30). VNet flow logs do not capture packet payloads or cover every PaaS internal hop.

## 3. Recommended Configuration Sequence

### Phase A: Verify Baseline Telemetry

1. Confirm the target workspace and list deployed resources, including the AKS managed `MC_` group.
2. Verify AMA extensions, managed identities, DCR associations, and outbound connectivity to Azure Monitor on both VMs.
3. Check service diagnostic settings, enabled categories, and `Dedicated` destination mode. Remember a table may not appear until its first ingested event.
4. Apply required Windows audit policies, ensuring no secrets are passed in command-line arguments.
5. Generate benign marker events from this guide and confirm arrival in Log Analytics.

Do not create a duplicate DCR from Sentinel's Content Hub *Windows Security Events via AMA* connector without inspecting the Terraform-managed DCR first: overlapping DCRs double-ingest events and double-bill.

### Phase B: Turn Telemetry into Detections

- Install applicable **Content Hub** solutions (Windows Security Events, Syslog, Azure Activity) if out-of-the-box templates are desired, adapting queries to `Dedicated` table schemas.
- Enable the opt-in Terraform scheduled rules (`enable_sentinel_analytics = true`) or create custom `LAB-` rules with entity mappings and incident creation.
- Enable **Auditing and health monitoring** in Sentinel Settings (`SentinelHealth` and `SentinelAudit`).
- Use the coverage workbook (`SOC L2 Lab - Generated Security Events`) and maintain a list of expected sources—counting events alone cannot distinguish a quiet source from a broken one.
- Keep initial SOAR automation focused on tagging, triage, and enrichment comments. Never automate IP blocking, VM isolation, or account disabling without separate approval.

### Phase C: Expand Visibility with Approved Budget

Add Entra ID logs, additional Defender plans, full AKS audit logs, VNet flow logs, or Application Insights according to investigation goals and approved budget.

### Permissions, Costs, and Responsibilities

| Action | Prerequisite |
| --- | --- |
| Query logs & investigate | `Log Analytics Reader` and `Microsoft Sentinel Reader` on the required scope. |
| Manage rules & incidents | `Microsoft Sentinel Contributor` for rules; `Microsoft Sentinel Responder` for incident triage. |
| Configure diagnostics & DCRs | Azure Monitor permissions on target resources; subscription scope required for `AzureActivity` diagnostics. |
| Configure tenant connectors/roles | Specific Entra ID / RBAC roles per connector; avoid granting `Global Administrator` for convenience. |
| Enable Defender & flow logs | Budget approval for Defender plans, Storage, and Traffic Analytics ingestion. |
| Code separation | Terraform manages cloud infrastructure, diagnostics, DCRs, and Sentinel resources; Ansible/guest scripts manage guest OS auditing, IIS/Apache, AD DS, and PostgreSQL. |

Keep tables queried by scheduled analytic rules on the **Analytics** tier; do not switch them to Basic or Auxiliary assuming scheduled rule compatibility.

## 4. Observing Results in Sentinel

In the Microsoft Defender portal (or Azure portal > Microsoft Sentinel), select the lab workspace:

1. **Raw Event:** run the corresponding KQL query in **Logs** / **Advanced Hunting (Workspace)**.
2. **Alert:** verify the scheduled analytic rule ran after ingestion and exceeded its threshold (`> 0`).
3. **Incident:** confirm incident creation is enabled and inspect mapped entities, timeline, comments, and tags.

Queries below use the **Log Analytics / Sentinel** workspace schema (not Defender XDR native `DeviceProcessEvents` / `AlertInfo` tables). If you encounter `Failed to resolve table`, either the table has not received its first record yet or the query scope points to the wrong workspace.

## 5. Test Preparation and Safety Rules

- Run exclusively against authorized lab resources within an agreed window.
- Record start/end UTC timestamps, target resource, test account, and source IP. Use `SOC-L2-Pxx` markers with zero personal data or real secrets.
- Allow 5–15 minutes for initial ingestion (up to 30 minutes on cold tables); measure actual pipeline delay using `ingestion_time()` where supported.
- Use unprivileged, disposable accounts for failed-logon tests. Check account lockout thresholds beforehand and never test passwords against real accounts.
- Never disable NSGs, Defender, MFA, or auditing; never open `0.0.0.0/0` inbound rules; never use real malware, exploitation payloads, or log tampering.
- Replace all `<...>` placeholders before running manual commands.

### PowerShell Automation

[Invoke-SocLabLogGeneration.ps1](../scripts/Invoke-SocLabLogGeneration.ps1) automates these benign tests from the administrator workstation using Azure CLI (`az vm run-command` for VMs and `az aks command invoke` for AKS—no local SSH, RDP, `kubectl`, or `kubelogin` required). Every execution stamps `SOC-L2-Pxx-<RunId>` markers, cleans up temporary Kubernetes namespaces and ARM tags, and writes ready-to-run KQL queries to `%TEMP%\soc-l2-loggen\<RunId>-queries.kql`.

| Group (`-Test`) | Tests | Sentinel Table(s) |
|---|---|---|
| `Windows` | P02 (multiple 4625 events with nonexistent users), P03 (multiple 4688 events with marker), P14 (Application Warning event), P15 (disposable AD user/group lifecycle: 4720/4722/4724/4725/4726/4727/4728/4729/4730/4732/4733/4738 and 4776) | `SecurityEvent`, `Event` |
| `Linux` | P04 (`logger` across `authpriv`/`auth`/`daemon` + benign `sudo` marker), P04B (failed SSH and `su` attempts with nonexistent `socp04<short>` users), P13 (failed PostgreSQL login) | `Syslog` (`auth`/`authpriv`/`daemon`, `sshd`/`su`, `local5`) |
| `WebServers` | P11 (Apache), P12 (IIS) | `Syslog` (`local6`), `W3CIISLog` |
| `AppService` | P05 (marked HTTPS requests) | `AppServiceHTTPLogs` |
| `KeyVault` | P07 (secret metadata list; `200` on `linux-ssh-public-key` if present and `404` on nonexistent secret; never reads passwords) | `AZKVAuditLogs` |
| `Arm` | P09 (`SOCPrueba` tag added and restored on Linux VM) | `AzureActivity` |
| `Aks` | P08 (namespace `soc-l2-p08-<RunId>` and ConfigMap), P10 (non-privileged pod writing to stdout), P10E (pod with nonexistent image tag triggering `ErrImagePull`) | `AKSAuditAdmin`, `ContainerLogV2`, `KubeEvents` (`Warning` events) |

```powershell
.\scripts\Invoke-SocLabLogGeneration.ps1 -WhatIf                 # Discover resources only
.\scripts\Invoke-SocLabLogGeneration.ps1 -Test Windows, Linux -Verify
.\scripts\Invoke-SocLabLogGeneration.ps1 -VerifyOnly -RunId <RunId>
```

Command-line arguments appear in cleartext in Event 4688 and Syslog; all passwords used in P02, P13, and P15 are synthetic invalid strings. P11, P12, and P13 require `enable_ansible`. P15 requires the Windows VM to be promoted as a domain controller (`ActiveDirectory` module) and deletes disposable accounts/groups in a `finally` block. With `-Verify`, the script polls the Log Analytics Query API until each marker is visible.

Terraform invokes it automatically as the final `apply` step when `enable_log_generation = true` (see [log_generation.tf](../log_generation.tf)), waiting for VM `Heartbeat`, AKS `KubePodInventory`, and diagnostic setting warm-up (`-WaitForSourcesMinutes`, `-InitialDelaySeconds`).

## 6. Controlled Tests and Expected Telemetry

### P01. Validate Agent Liveness Across Both VMs

**Action:** keep both VMs running with AMA healthy. Note actual computer names: Windows is configured as `soc-win` (`soc-win.lab.example.test` after AD promotion), while its Azure VM resource name is `<prefix>-windows`.

```kql
let Expected = datatable(Host:string)
[
    "soc-l2-linux",
    "soc-win"
];
Expected
| join kind=leftouter (
    Heartbeat
    | where TimeGenerated > ago(24h)
    | extend Host = tolower(tostring(split(Computer, ".")[0]))
    | summarize LastHeartbeat = max(TimeGenerated) by Host
) on Host
| extend Status = case(
    isnull(LastHeartbeat), "No heartbeat in 24h",
    LastHeartbeat < ago(10m), "Delayed",
    "Recent")
| project Host, LastHeartbeat, Status
```

**Expected:** two rows, both `Recent`. Silent hosts still appear via the left-outer join. Adjust hostnames if `name_prefix` was customized.

### P02. Windows Authentication Failures

**Prerequisites:** Logon/Failure auditing enabled, nonexistent or disposable unprivileged account, and Event 4625 collection in DCR.

**Manual action:** trigger up to three failed logon attempts with a nonexistent test account within five minutes from an authorized session.

```kql
SecurityEvent
| where TimeGenerated > ago(5m)
| where EventID == 4625
| where Computer startswith "soc-win"
| summarize Attempts = count(), FirstSeen = min(TimeGenerated),
    LastSeen = max(TimeGenerated) by Computer, TargetUserName, IpAddress
| where Attempts >= 2
```

**Expected:** row showing host, target account, source IP (when populated), and attempt count. Network-level blocks (NSG/NLA drops prior to authentication) will not emit 4625.

**Expected incident:** `LAB-P02 - Windows Authentication Failures (Brute Force)` (High severity in `sentinel.tf`), mapping Account, Host, and IP entities.

### P03. Benign Process Creation Auditing

**Prerequisites:** *Audit Process Creation* and *Include command line in process creation events* enabled via [Configure-WindowsAudit.ps1](../scripts/Configure-WindowsAudit.ps1).

**Action in PowerShell on Windows:**

```powershell
cmd.exe /c "echo SOC-L2-P03"
```

```kql
SecurityEvent
| where TimeGenerated > ago(30m)
| where EventID == 4688
| where Computer startswith "soc-win"
| where CommandLine contains "SOC-L2-P03"
| project TimeGenerated, Computer, SubjectUserName, NewProcessName, CommandLine
| order by TimeGenerated desc
```

**Expected:** at least one `cmd.exe` event containing `SOC-L2-P03` in `CommandLine`. Never include real credentials in command arguments.

**Expected incident:** `LAB-P03 - Suspicious Process Execution on Windows` (Medium severity).

### P04. End-to-End Linux Syslog Validation

**Action on Ubuntu:**

```bash
logger -p authpriv.notice -t soc-lab "SOC-L2-P04 benign ingestion test"
```

```kql
Syslog
| where TimeGenerated > ago(30m)
| where SyslogMessage contains "SOC-L2-P04"
| project TimeGenerated, Computer, Facility, SeverityLevel,
    ProcessName, SyslogMessage
| order by TimeGenerated desc
```

**Expected:** record with facility `authpriv`, tag `soc-lab`, and the test marker. Companion test **P04B** exercises failed `sshd` and `su` attempts with nonexistent `socp04*` users, triggering `LAB-P04B - Linux SSH and su Brute Force`.

### P05. Marked HTTPS Request to App Service

**Prerequisites:** App Service reachable directly over HTTPS.

```powershell
curl.exe --max-time 15 -A "SOC-L2-Lab" -i "https://<APP_NAME>.azurewebsites.net/SOC-L2-P05-nonexistent"
```

```kql
AppServiceHTTPLogs
| where TimeGenerated > ago(30m)
| where CsUriStem contains "SOC-L2-P05"
| project TimeGenerated, CsHost, CsMethod, CsUriStem, ScStatus, CIp, UserAgent
```

**Expected:** entry in `AppServiceHTTPLogs`. Requests returning `ScStatus >= 400` with `UserAgent startswith "SOC-L2-Lab"` trigger `LAB-P05 - Web Scanning and Reconnaissance on App Service`.

### P06. Deterministic WAF Block with Benign Header Marker (Historical Reference)

**Not applicable to the current deployment.** Application Gateway/WAF was removed from the codebase; retained solely for architectural reference. Do not deploy WAF resources without new scope approval.

Previously proposed setup: custom WAF rule matching header `X-SOC-Lab-Test: SOC-L2-P06` with `Block` action in Prevention mode, queried via `AGWFirewallLogs | where Action =~ "Blocked" and RequestUri contains "SOC-L2-P06"`.

### P07. Audited Key Vault Secret Access

**Prerequisites:** use only `linux-ssh-public-key` (which stores an SSH public key) and/or a nonexistent secret name `soc-l2-p07-*`. Never read `windows-admin-password` or `windows-dsrm-password` for testing.

```powershell
az keyvault secret show --vault-name <VAULT_NAME> --name linux-ssh-public-key --query id -o tsv
az keyvault secret show --vault-name <VAULT_NAME> --name soc-l2-p07-nonexistent --query id -o tsv
```

```kql
AZKVAuditLogs
| where TimeGenerated > ago(30m)
| where OperationName =~ "SecretGet"
| where RequestUri contains "linux-ssh-public-key" or RequestUri contains "soc-l2-p07"
| project TimeGenerated, OperationName, HttpStatusCode,
    ResultType, ResultSignature, CallerIpAddress, Identity, RequestUri
```

**Expected:** `SecretGet` with `200` on `linux-ssh-public-key` and `404` on `soc-l2-p07-nonexistent`, triggering `LAB-P07 - Unauthorized or Denied Access in Key Vault`.

### P08. Benign Kubernetes Administrative Modification

**Prerequisites:** authorized `kubectl` context for the lab AKS cluster (or `az aks command invoke`) and unused namespace `soc-l2-p08`.

```powershell
kubectl config current-context
kubectl create namespace soc-l2-p08
kubectl create configmap soc-l2-p08 --namespace soc-l2-p08 --from-literal=marker=SOC-L2-P08
```

```kql
AKSAuditAdmin
| where TimeGenerated > ago(30m)
| where Verb in ("create", "delete")
| where tostring(ObjectRef.namespace) == "soc-l2-p08"
| where tostring(ObjectRef.resource) == "configmaps"
| extend User = tostring(User.username),
    StatusCode = toint(ResponseStatus.code),
    ObjectName = tostring(ObjectRef.name)
| project TimeGenerated, Verb, User, ObjectName, StatusCode,
    SourceIps, AuditId, Stage
```

**Expected:** ConfigMap creation (`201`) logged in `AKSAuditAdmin`, triggering `LAB-P08 - Kubernetes Administrative Modifications`. Remember `AKSAuditAdmin` excludes `get`/`list` reads.

**Cleanup (only objects created for this test):**

```powershell
kubectl delete configmap soc-l2-p08 --namespace soc-l2-p08
kubectl delete namespace soc-l2-p08
```

### P09. Reversible ARM Tag Modification

**Action:** merge temporary tag `SOCPrueba=SOC-L2-P09` on a lab VM and immediately delete/restore it afterward. Never overwrite existing tags or alter NSGs/RBAC to generate test noise.

```kql
AzureActivity
| where TimeGenerated > ago(30m)
| where ResourceGroup =~ "soc-l2-rg"
| where OperationNameValue in~ (
    "MICROSOFT.COMPUTE/VIRTUALMACHINES/WRITE",
    "MICROSOFT.RESOURCES/TAGS/WRITE")
| project TimeGenerated, OperationNameValue, ActivityStatusValue,
    Caller, CallerIpAddress, ResourceId, CorrelationId
| order by TimeGenerated desc
```

**Expected:** tag write operations in `AzureActivity`, triggering `LAB-P09 - Suspicious ARM Tag Modification`.

## 7. Analytic Rule Design for Incident Generation

Initial design guidance for `LAB-` scheduled rules uses 5-minute execution frequency (`PT5M`), threshold `> 0`, incident creation enabled with 1-hour entity grouping (`PT1H`), and entity mappings for Host, Account, and IP where valid:

| Proposed Rule | Baseline Logic | Design Severity | Entities / Details |
| --- | --- | --- | --- |
| LAB-P01 - Missing Heartbeat | P01 query filtered to `Status != "Recent"`; 5 min frequency, 24h lookback | Medium | Host; exclude planned maintenance/shutdowns |
| LAB-P02 - Windows Auth Failures | P02: failed 4625 attempts by host/account/IP | Medium / High | Host, Account, IP |
| LAB-P03 - Process Marker | P03 within 15 min window | Low / Medium | Host, Account; `CommandLine` |
| LAB-P04 - Syslog Validation | P04 within 15 min window | Low | Host; facility and message |
| LAB-P06 - WAF Block | Disabled / do not create (WAF removed) | Low | Historical reference only |
| LAB-P07 - Key Vault Denied/Failed | P07 within 15 min window (`HttpStatusCode >= 400`) | Low / Medium | IP |
| LAB-P08 - Kubernetes Admin Change | P08 within 15 min window (`create`/`update`/`delete`) | Low / Medium | User and URI details |
| LAB-P09 - ARM Tag Change | P09 within 15 min window (`MICROSOFT.RESOURCES/TAGS/*`) | Low / Medium | Account, IP |

- Overlapping windows (e.g., 15-minute lookback every 5 minutes) can evaluate the same event multiple times; alert grouping (`PT1H`) consolidates alerts into a single incident.
- Close verified workshop test incidents as **Benign Positive – Suspicious but expected** (authorized testing) with a closing note.

> **Implemented in Terraform (opt-in).** With `enable_sentinel_analytics`, [sentinel.tf](../sentinel.tf) deploys 13 scheduled `LAB-Pxx` rules (`P02`, `P15`, `P04B` as `High`; `P03`, `P05`, `P07`, `P08`, `P09`, `P10`, `P11`, `P12`, `P13`, `P14` as `Medium`—severities are set to `High`/`Medium` so incidents clear Defender XDR's default Priority Score 15–100 filter) along with entity mappings and an automation rule. With `enable_sentinel_playbooks`, two Logic App playbooks (enrich comment and tag/triage) run automatically on `LAB-` incidents. P01, P04, and P06 remain unimplemented proposals. **Where severities, lookback windows, or frequencies differ between this design table and `sentinel.tf`, the Terraform implementation takes precedence.** See the "Sentinel Content" section in [README.md](../README.md).

## 8. Workbook and Coverage Monitoring

Recommended workbook sections:

1. **Expected vs. Received Inventory:** resource ID, log source, target table, owner, criticality, and last verified timestamp.
2. **Virtual Machines:** P01 agent liveness table and Heartbeat trend.
3. **Security Signals:** Windows logon failures by account, Linux Syslog events, Key Vault secret operations/failures, Kubernetes admin audit, and ARM tag changes.
4. **Web Services:** App Service HTTP requests/status codes, plus Apache (`local6`) and IIS (`W3CIISLog`).
5. **Sentinel Operations:** `SentinelHealth` errors, `SentinelAudit` rule modifications, and active `LAB-` incidents.
6. **Ingestion Volume:** billable data volume by table to spot unexpected spikes early.

Billable ingestion volume query (informational volume, not a final invoice):

```kql
Usage
| where TimeGenerated > ago(24h)
| where IsBillable == true
| summarize VolumeMB = sum(Quantity) by DataType, QuantityUnit
| order by VolumeMB desc
```

> **Implemented in Terraform (opt-in).** With `enable_sentinel_analytics`, [sentinel.tf](../sentinel.tf) deploys workbook `SOC L2 Lab - Generated Security Events` ([files/soc-workbook.json](../files/soc-workbook.json)) with per-test panels. With `enable_sentinel_notebooks`, [sentinel_notebooks.tf](../sentinel_notebooks.tf) deploys an Azure ML workspace and compute instance and automatically uploads [SOC-L2-Events.ipynb](../notebooks/SOC-L2-Events.ipynb), [SOC-L2-Hunting.ipynb](../notebooks/SOC-L2-Hunting.ipynb), and [SOC-L2-Log-Analysis.ipynb](../notebooks/SOC-L2-Log-Analysis.ipynb) via `terraform_data.upload_notebooks`. Stop the compute instance when finished to avoid hourly charges.

## 9. Evidence Log and Acceptance Criteria

Record per test execution:

| Field | Content |
| --- | --- |
| Test & authorization | Test ID (`P01`–`P15`), operator, and approved time window |
| Source | Workspace, resource ID, test identity, and source IP (no secrets) |
| Generation | UTC timestamp, `RunId` marker, and benign command output |
| Ingestion | Target table, earliest `TimeGenerated`, `ingestion_time()`, and KQL row count |
| Detection | Analytic rule name, execution timestamp, alert ID, and incident number |
| Investigation | Verified entities, enrichment comment/tags, and benign classification |
| Cleanup | Temporary namespaces, tags, and disposable AD accounts/groups removed |

Acceptance criteria:

- **Ingestion passed:** expected marker appears in its target table matching resource, time window, and `RunId`; both VMs report in P01.
- **Detection passed:** KQL rule fires and creates the corresponding `LAB-Pxx` alert and incident.
- **Incomplete coverage:** missing table, unmonitored resource, or absent marker—never claim "100% monitored" based solely on `Heartbeat`.
- **Closure:** temporary artifacts cleaned up and ingestion latency documented.

## 10. Official References

- [Connect Azure, Windows, and Microsoft services to Sentinel](https://learn.microsoft.com/azure/sentinel/connect-azure-windows-microsoft-services).
- [Monitor the health and audit the integrity of Microsoft Sentinel](https://learn.microsoft.com/azure/sentinel/enable-monitoring).
- [Command-line process auditing and Event 4688](https://learn.microsoft.com/windows-server/identity/ad-ds/manage/component-updates/command-line-process-auditing).
- [AGWFirewallLogs](https://learn.microsoft.com/azure/azure-monitor/reference/tables/agwfirewalllogs) and [AGWAccessLogs](https://learn.microsoft.com/azure/azure-monitor/reference/tables/agwaccesslogs) schemas.
- [AppServiceHTTPLogs schema](https://learn.microsoft.com/azure/azure-monitor/reference/tables/appservicehttplogs).
- [AZKVAuditLogs schema](https://learn.microsoft.com/azure/azure-monitor/reference/tables/azkvauditlogs).
- [AKSAuditAdmin schema and exclusion of get/list](https://learn.microsoft.com/azure/azure-monitor/reference/tables/aksauditadmin).
- [Virtual network flow logs overview](https://learn.microsoft.com/azure/network-watcher/vnet-flow-logs-overview).
- [NSG flow logs retirement and migration](https://learn.microsoft.com/azure/network-watcher/nsg-flow-logs-migrate).
