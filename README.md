**English** | [Español](README.es.md)

# Azure SOC L2 Cyber Range: Threat Detection & Incident Response with IaC
### Ephemeral Cloud Cybersecurity Lab with Terraform, Ansible, and Microsoft Sentinel

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Terraform CI](https://github.com/soysoliscarlos/sentinel-soc-lab/actions/workflows/terraform-ci.yml/badge.svg)](.github/workflows/terraform-ci.yml)

> **Official GitHub Repository:** [https://github.com/soysoliscarlos/sentinel-soc-lab](https://github.com/soysoliscarlos/sentinel-soc-lab)

> **Presentation:** This repository includes the talk slides in PDF (Spanish): [Bootcamp Analista SOC Nivel 2 2026 - Comunidad DOJO.pdf](slides/Bootcamp%20Analista%20SOC%20Nivel%202%202026%20-%20Comunidad%20DOJO.pdf).

Proposed operational guide: [Sentinel coverage and controlled testing](docs/Sentinel-Coverage-and-Testing.md), covering pending log sources, KQL queries, and incident examples. It does not add infrastructure or run tests against Azure.

## Confirmed Scope

Infrastructure code for a lab in `eastus2`. The baseline deployment was initiated by the user; Application Gateway/WAF was removed from the code at the user's request. This change does not run deletions in Azure or simulations. Local validation does not prove regional availability, permissions, quotas, or actual log delivery.

| Component | Initial Configuration | Telemetry to Sentinel Workspace |
| --- | --- | --- |
| Ubuntu 22.04 LTS | D2s_v6, SSH key, static Standard public IP | AMA + DCR: authentication, daemon, kernel, and system `Syslog`; `Heartbeat`. With Ansible: Apache `local6` and PostgreSQL `local5`, prepared without applying |
| Windows Server 2022 | D2s_v6, RDP, static Standard public IP | AMA + DCR: `SecurityEvent`, System and Application errors/warnings in `Event`; `Heartbeat`. Logon/process auditing and 4688 command-line arguments prepared. With Ansible: IIS `W3CIISLog` and AD DS auditing/channels, not yet applied |
| App Service Linux | B1 plan, HTTPS endpoint, no deployed application | HTTP, console, publish audit, IP restrictions, and platform logs in `AppService*` tables |
| AKS | Free tier, 2 D4s_v6 nodes, Azure CNI Overlay, Entra ID, and Azure RBAC | Container Insights: `ContainerLogV2`, `KubeEvents`, `KubePodInventory`; diagnostics: `AKSAuditAdmin` and `AKSControlPlane`. `guard` added to code, not yet applied |
| Log Analytics | PerGB2018, 30 days, 1 GB/day cap, local authentication disabled | Single shared workspace for all sources |
| Microsoft Sentinel | Dedicated onboarding on the workspace | Queryable data; base onboarding does not include analytic rules or playbooks |
| Key Vault Standard | Private Endpoint and Private DNS; public endpoint restricted to `admin_source_cidr`, with RBAC | `AuditEvent` auditing to `AZKVAuditLogs` |
| Azure Activity | Subscription diagnostic setting, eight categories | `AzureActivity`, includes non-lab resources within the same subscription |

**Confirmed design change:** the initial single D2 node profile was replaced with two D4s_v5 (later D4s_v6) nodes to comply with current AKS system node pool requirements: minimum two nodes and at least a 4 vCPU / 4 GB SKU, excluding B-series. Free refers only to the cluster management tier, not to the nodes or other resources.

**Adjustment after the first apply (2026-10-22):** in the target subscription, `eastus2` returns `NotAvailableForSubscription` for B-series and Dv5-series (VMs failed with `SkuNotAvailable` and AKS rejected D4s_v5). VMs switched to `Standard_D2s_v6` and AKS to `Standard_D4s_v6`, which are available except in zone 2 (the code does not pin availability zones). The Dsv6 family has a 350 vCPU quota and the regional total vCPU limit is 65; the stack uses 12 (+4 surge during AKS upgrades). Check before changing VM sizes with `az vm list-skus --location eastus2 --size <SKU> --all -o table` and `az vm list-usage --location eastus2 -o table`.

Terraform manages infrastructure, identities, roles, AMA agents, and collection rules. Cloud-init ensures `rsyslog` on Ubuntu. A Custom Script Extension configures Windows logon/process auditing via [Configure-WindowsAudit.ps1](scripts/Configure-WindowsAudit.ps1), pending apply. [Ansible invoked from Terraform](Ansible/README.md) installs IIS and a `lab.example.test` AD forest on Windows, and Apache/PostgreSQL on Ubuntu. `enable_ansible` defaults to `false`, but **is enabled in the lab inputs; it has not been executed against Azure in this change**. Its SSH bootstrap is integrated into the same Windows extension, preserving the audit configuration.

After installing and verifying services, Ansible configures their logs and Terraform expands the existing DCRs to the same workspace: IIS W3C, AD DS auditing/channels, Apache log files via rsyslog, and PostgreSQL via Syslog. **Full SQL logging is authorized via `log_statement='all'`: it may record secrets and personal data and significantly increase ingestion.** Existing daily caps and retention are not disabled; review [paths, limits, and verification queries](Ansible/README.md#telemetry-and-references). Out of scope: Sysmon, undeclared audit policies, custom applications, Kubernetes user workloads, and attack simulations. Defender for Servers, detection rules, and hunting queries are opt-in and described under "Sentinel Content".

No legacy Azure Activity connectors or MMA/OMS agents are created on VMs. The Terraform `oms_agent` block is the legacy AzureRM schema name for the AKS monitoring add-on using managed identity authentication; its explicit DCR and association are also configured. Onboarding does not install Content Hub solutions or configure Entra ID / Microsoft 365 connectors.

### Optional Component Creation

The four boolean switches in [terraform.tfvars](terraform.tfvars) default to `true`:

```hcl
create_app_service = true
create_linux_vm    = true
create_windows_vm  = true
create_aks         = true
```

Each `false` excludes the component and its dedicated dependencies: App Service plan; each VM's public IP, NIC, NSG, credentials, extensions, and DCR; AKS subnet, identity, roles, and Container Insights. The VM subnet is kept as long as at least one VM is enabled. Disabled component outputs evaluate to `null` (omitted by Terraform).

By confirmed design, `enable_ansible = true` **requires both VMs enabled**; validation rejects any other combination. To skip a VM, also set `enable_ansible = false`. Shared services (resource group, VNet, Key Vault with Private Endpoint/DNS, Log Analytics, Sentinel, and Azure Activity) remain active and may incur charges.

**Setting `false` does not pause an existing resource: Terraform will propose destroying it on the next plan/apply.** Review costs, permissions, data loss, and the execution plan before applying. Conditional `[0]` instances avoid unnecessary replacements when components remain enabled.

### Log Generation at the End of Deployment

[log_generation.tf](log_generation.tf) defines `terraform_data.log_generation`, which runs [Invoke-SocLabLogGeneration.ps1](scripts/Invoke-SocLabLogGeneration.ps1) via `local-exec` as the **final step of `apply`**. It depends on:

- Ansible and AMA extensions, including Windows auditing.
- All three DCR associations (Linux, Windows, and AKS).
- Diagnostic settings for App Service, AKS, Key Vault, and Activity Log.
- Sentinel onboarding and AKS / Key Vault role assignments.

Resource creation alone does not guarantee telemetry is flowing yet. Therefore, the script first waits for `Heartbeat` from enabled VMs and `KubePodInventory` from AKS (if present and selected), up to `log_generation_wait_minutes` (30). Next, it waits `log_generation_initial_delay_seconds` (300) for newly created diagnostic settings to start exporting. If a source does not report in time, it fails without generating test activity. Resource-less groups are reported as `Skipped`; `WebServers` requires both VMs and `Arm` uses the Linux VM. P07 lists secret metadata and reads `linux-ssh-public-key` only if it exists; without Linux it generates only `SecretList` and a failed `SecretGet` on a nonexistent secret name, never reading passwords.

Each run produces varied, benign activity: on Windows, multiple 4625 events with nonexistent users (P02), multiple 4688 processes (P03), and disposable domain user/group lifecycle events (P15: 4720/4722/4724/4725/4726/4727/4728/4729/4730/4732/4733/4738 and 4776), created and deleted within the same step; on Linux, `logger` entries across facilities (P04) and failed SSH/`su` attempts with nonexistent users (P04B). P15 requires the Windows VM to be a domain controller (`ActiveDirectory` module).

| Variable | Default | Purpose |
| --- | --- | --- |
| `enable_log_generation` | `false` (enabled in `terraform.tfvars`) | Opt-in benign activity generation |
| `log_generation_tests` | `["All"]` | `Windows`, `Linux`, `WebServers`, `AppService`, `KeyVault`, `Arm`, `Aks` |
| `log_generation_verify` | `true` | Queries each marker; pending ingestion is reported without failing `apply` |
| `log_generation_trigger` | `"initial"` | Changing this re-runs the tests on the next `apply` |

Requirements on the machine running Terraform:
- Azure CLI logged into the target subscription.
- Windows PowerShell.
- Egress from `admin_source_cidr`, required by HTTP, Key Vault, and the AKS API.

It runs only on creation, or when the trigger, selected tests, script, or any DCR association/diagnostic setting changes. If generation fails, `apply` fails and Terraform retries the resource on the next `apply`. Test P09 updates a tag outside Terraform and restores it within the same step, leaving no drift.

## Sentinel Content

Beyond onboarding, this repository can deploy Sentinel content that **surfaces the events generated by the script** ([sentinel.tf](sentinel.tf), [sentinel_playbooks.tf](sentinel_playbooks.tf), [sentinel_notebooks.tf](sentinel_notebooks.tf)). Everything is **opt-in** and disabled by default; `terraform.tfvars` enables it for the workshop.

| Switch | Default | What It Creates | Prerequisites |
| --- | --- | --- | --- |
| `enable_sentinel_analytics` | `false` (enabled in `terraform.tfvars`) | 13 scheduled `LAB-Pxx` analytic rules, 1 workbook, 2 hunting queries (HUNT-01/HUNT-02 in `sentinel_hunting.tf`), and 1 automation rule | Sentinel onboarding |
| `enable_sentinel_playbooks` | `false` (enabled in `terraform.tfvars`) | 2 playbooks (Logic Apps) and their role assignments | Requires `enable_sentinel_analytics`; `Microsoft.Logic` and `Microsoft.Web` RPs |
| `enable_sentinel_notebooks` | `false` (enabled in `terraform.tfvars`) | Azure ML workspace (Storage, Key Vault, App Insights) and a compute instance | `Microsoft.MachineLearningServices` RP |

Because the provider sets `resource_provider_registrations = "none"`, register the required RPs manually before running `apply` with playbooks or notebooks enabled:

```powershell
az provider register --namespace Microsoft.Logic
az provider register --namespace Microsoft.Web
az provider register --namespace Microsoft.MachineLearningServices
```

### Analytic Rules and Workbook

Each rule queries a test marker and creates a `LAB-Pxx` incident. Rule, workbook, and automation rule resource names are GUIDs (`random_uuid`), as required by the API. They are configured with `PT5M` frequency (evaluated every 5 minutes) and `High` / `Medium` severities so incidents receive a *Priority Score* $\ge 15$ and appear directly in the unified Microsoft Defender XDR portal (**Incidents**) without being hidden by the default `Priority score: 15 - 100` filter.

| Rule | Severity | Test and Marker Detected |
| --- | --- | --- |
| `LAB-P02 - Windows Authentication Failures (Brute Force)` | High | 4625 with nonexistent `soc-l2-p02-*` accounts ($\ge 2$ attempts) |
| `LAB-P15 - Anomalous AD Account and Group Management` | High | Creation/modification/deletion of disposable `SOCp15/SOCg15` accounts and groups |
| `LAB-P03 - Suspicious Process Execution on Windows` | Medium | 4688 containing `SOC-L2-P03` in `CommandLine` |
| `LAB-P04B - Linux SSH and su Brute Force` | High | Failed SSH and `su` attempts with nonexistent `socp04*` users |
| `LAB-P05 - Web Scanning and Reconnaissance on App Service` | Medium | Suspicious paths/methods with `SOC-L2-Lab` User-Agent |
| `LAB-P07 - Unauthorized or Denied Access in Key Vault` | Medium | Failed read of nonexistent secret `soc-l2-p07` |
| `LAB-P08 - Kubernetes Administrative Modifications` | Medium | Object creation/modification in namespace `soc-l2-p08` (AKS admin audit) |
| `LAB-P09 - Suspicious ARM Tag Modification` | Medium | Unauthorized `SOCPrueba` tag modification in `AzureActivity` |
| `LAB-P10 - Warning Event in AKS Pods` | Medium | Kubernetes `Warning` events in `KubeEvents` from test pods |
| `LAB-P11 - Anomalous HTTP Request on Apache Server` | Medium | Marked HTTP requests to Apache in `Syslog local6` |
| `LAB-P12 - Suspicious HTTP Request on IIS Server` | Medium | Marked web probe or access in `W3CIISLog` |
| `LAB-P13 - PostgreSQL Database Authentication Failure` | Medium | Failed connection attempts with invalid user in `Syslog local5` |
| `LAB-P14 - Suspicious Event in Windows Application Log` | Medium | Warning event generated by source `SOC-L2-Lab` in `Event` |

The workbook `SOC L2 Lab - Generated Security Events` ([files/soc-workbook.json](files/soc-workbook.json)) groups panels by test with a time-range parameter. Open it under **Sentinel > Workbooks > My workbooks** or **Azure Monitor > Workbooks**.

### Playbooks and Automation

Playbooks are deployed as ARM templates ([files/playbook-enrich-comment.json](files/playbook-enrich-comment.json) and [files/playbook-tag-triage.json](files/playbook-tag-triage.json)) because managed-identity API connections cannot be natively expressed with `azurerm_api_connection`:

- **enrich** adds an enrichment comment to the incident.
- **triage** sets the incident status to `Active` and adds the `SOC-L2-Lab` and `Workshop` labels.

The automation rule `LAB - Tag and Enrich Workshop Incidents` filters on incident titles containing `LAB-`, adds the `SOC-L2-Lab` label (order 1), and runs both playbooks (order 2 and 3). Role assignments created:

- Each playbook (its system-assigned managed identity): **Microsoft Sentinel Responder** on the resource group.
- Sentinel's service principal (`Azure Security Insights`): **Microsoft Sentinel Automation Contributor** on the resource group, required for automation rules to invoke playbooks.

> **Pending verification in the portal:** the connector paths (`/Incidents/Comment`, `PUT /Incidents`) and the `tagsToAdd` payload follow exported playbook conventions, but have not been verified against this tenant. After the first `apply`, open each Logic App, authorize the `azuresentinel` connection if prompted, and verify that actions run cleanly, adjusting the JSON if required by the portal.

### Notebooks (Azure Machine Learning)

[sentinel_notebooks.tf](sentinel_notebooks.tf) creates an Azure ML workspace with its Storage Account, Key Vault, and Application Insights, plus a compute instance (`Standard_DS2_v2` by default, variable `sentinel_notebook_compute_size`). The compute instance's managed identity receives **Log Analytics Reader** on `soc-l2-law` so notebooks can query logs via `DefaultAzureCredential`.

All three notebooks ([SOC-L2-Events.ipynb](notebooks/SOC-L2-Events.ipynb), [SOC-L2-Hunting.ipynb](notebooks/SOC-L2-Hunting.ipynb), and [SOC-L2-Log-Analysis.ipynb](notebooks/SOC-L2-Log-Analysis.ipynb)) are automatically uploaded to the workspace file share via `terraform_data.upload_notebooks` (using `az storage file upload`, which requires an authenticated Azure CLI). If upload fails, you can upload them manually in **Azure ML Studio > Notebooks**.

### Defender for Servers and Hunting Queries

- [defender.tf](defender.tf): `enable_defender_for_servers` enables Defender for Servers (P1/P2 subplan per variable), WDATP integration (`azurerm_security_center_setting`), and the `MDE.Windows` / `MDE.Linux` extensions. **This setting applies to the entire subscription and incurs charges**; review before applying.
- [sentinel_hunting.tf](sentinel_hunting.tf): 2 saved searches (HUNT-01 and HUNT-02) for proactive threat hunting, gated by `enable_sentinel_analytics`.

> **Cost note:** the compute instance **bills hourly while running** and has no auto-shutdown setting in the provider. Stop it manually in the portal or configure an auto-shutdown schedule when not in use. Validate VM family quotas before changing sizes.

## Live Verification of Connections and Ingestion

Read-only review conducted on the night of 2026-10-22, with records up to approximately **2026-10-23 02:14 UTC**. Verified resource group `soc-l2-rg`, managed resource group `MC_soc-l2-rg_soc-l2-aks_eastus2`, and workspace `soc-l2-law`; Sentinel has `default` onboarding. No changes were applied and no synthetic test events were generated during that review.

- Both AMA extensions report `Succeeded`, with valid DCR associations targeting the shared workspace. Source `_ResourceId` values were verified, not just table names.
- AKS is `Running`/`Succeeded`, with Container Insights enabled, managed identity authentication, and valid DCR/association. Both nodes send `Heartbeat`.
- App Service, Key Vault, and AKS diagnostic settings point to the workspace with `Dedicated` destination type. Subscription Activity Log exports all eight expected categories.
- The workspace retains 30 days, a 1 GB/day quota, and `RespectQuota` ingestion status at the time of review. This does not guarantee the cap will not be reached later.

| Source | Live Evidence (Last 24h) | Conclusion and Limitation |
| --- | --- | --- |
| Ubuntu `soc-l2-linux` | `Heartbeat` and `Syslog` with matching `_ResourceId` | Connection and ingestion verified; does not replace `auditd` for process/file auditing |
| Windows `soc-l2-windows` / `soc-win` | `Heartbeat`, 253 `SecurityEvent`, and 2 `Event` | Connection and ingestion verified. None of the 221 queried 4688 events included `CommandLine`; fix prepared |
| App Service `soc-l2-web` | 56 HTTP, 99 console, 32 IP restriction, and 270 platform logs | Four paths verified; publish auditing is configured, but without events end-to-end delivery is unconfirmed |
| AKS `soc-l2-aks` | 12,421 `AKSAuditAdmin`, 394 control plane, 27 `KubeEvents`, 336 `KubePodInventory`, 2 node Heartbeats | Ingestion verified for those sources. `ContainerLogV2` had zero events; recent inventory only showed `kube-system`, whose stdout/stderr are excluded by default unless configured otherwise |
| Key Vault `soc-l2-kv01` | 7 `AZKVAuditLogs` | Auditing with matching vault ID; no secrets were read during this review |
| Support resources and AKS managed group | `AzureActivity` showing operations in both resource groups | ARM control-plane coverage for VNet, NSG, NIC, IP, disks, Private DNS, Private Endpoint, identities, plan, and managed resources; does not cover network traffic or data plane |

Counts represent a single point-in-time query snapshot, not health thresholds or a guarantee of future coverage. No app publish or workload deployment was executed to force events. An authorized test with a non-system application/container is needed to validate silent paths.

**Prepared changes (pending apply):**

1. Added AKS diagnostic category `guard` to capture authentication telemetry. Does not enable the tenant Entra ID connector or include Kubernetes `get`/`list` read events.
2. Extension `ConfigureWindowsAudit` enables Logon and Process Creation by language-independent GUIDs, prioritizes advanced audit subcategories, and sets `ProcessCreationIncludeCmdLine_Enabled`. The script fails explicitly if `auditpol` or registry updates fail. Does not enable Sysmon, PowerShell Script Block Logging, or full account management policies.
3. [Terraform tests](tests/lab.tftest.hcl) verify destinations, associations, full categories, streams/sources, dedicated schemas, and the audit extension. Adding Ansible/logging brings local validation to **mock-provider test runs**, alongside `terraform fmt -check` and `terraform validate`. Windows scripts are tested with local doubles; this does not prove live ingestion from newly configured services.

The extension runs inside the VM as `SYSTEM` during `terraform apply`; it does not require Ansible or an extra service. **Process command-line arguments will be recorded in cleartext in logs**, so never pass secrets on the command line. Review workspace access and any GPOs that might overwrite local audit policy. Removing the extension does not revert audit policies; any rollback must be explicit. Enabling additional categories can increase ingestion and cost even without adding paid plans.

To verify the Windows fix later without generating artificial events:

```kusto
SecurityEvent
| where TimeGenerated > ago(30m)
| where Computer startswith "soc-win" and EventID == 4688
| summarize Processes=count(), WithArguments=countif(isnotempty(CommandLine))
```

Scope the time window to after the extension is applied. Zero events do not prove anything; if new 4688 events arrive without `CommandLine`, inspect local policy and event XML before considering the fix verified.

**Out of scope for this baseline coverage:** network/packet flow logs, tenant-level Entra ID logs, Defender plans (unless opted in), Sysmon, and full AKS `kube-audit` read logs. Resource metrics are not indiscriminately exported to Log Analytics. Per-resource diagnostics cannot substitute for those sources. A residual `soc-l2-waf` policy was observed in Azure without an Application Gateway: it provides no active protection or WAF telemetry and is untouched by this review.

## Network and Access

- VNet `10.20.0.0/16`, VM subnet `10.20.1.0/24`, and AKS subnet `10.20.2.0/24`. Pods `10.244.0.0/16`, services `10.30.0.0/16`.
- Each VM NIC has its own NSG: by default only SSH or RDP from `admin_source_cidr` is allowed; all other inbound traffic—including lateral VNet traffic—is denied. With `enable_ansible = true`, Windows SSH and HTTP on both VMs are also allowed from that same CIDR, and Windows receives static private IP `10.20.1.10`. PostgreSQL and AD ports are never exposed. Guest OS firewalls remain enforced.
- `admin_source_cidr` is required, public IPv4, `/24` to `/32`; using the administrator's exact `/32` egress IP is recommended. `10.10.0.0/16` was rejected because private ranges do not identify Internet egress.
- The AKS API server restricts access to that same CIDR with local accounts disabled. Nodes have no individual public IPs; AKS uses a Standard Load Balancer for outbound traffic.
- App Service allows direct public HTTPS access, without Application Gateway, WAF, Private Endpoint, or VNet integration. SCM/Kudu does not inherit restrictions from a removed Gateway subnet.
- AMA and AKS connect to public Azure Monitor endpoints. Do not block outbound traffic to Entra ID, Azure Monitor, ARM, package repositories, or AKS control-plane endpoints; there is no Azure Firewall, NAT Gateway, or Bastion.
- The Log Analytics workspace allows authenticated public network ingestion and querying; anonymous queries are not possible. No AMPLS / Private Link Scope is deployed.
- Key Vault has a Private Endpoint in `10.20.3.0/24` and links `privatelink.vaultcore.azure.net` to the VNet. Resources inside the VNet resolve the standard vault hostname to its private IP. The public endpoint remains enabled exclusively for `admin_source_cidr`, with `default_action = "Deny"` and `bypass = "None"`. Network access via Private Endpoint does not bypass authorization: explicit Azure RBAC roles are still mandatory.

## Complete Requirements to Build and Configure the Lab

To deploy and operate this end-to-end SOC L2 lab, meet the following requirements across Azure (Tenant, Subscription, RBAC Roles, Resource Providers, and Quotas), the operator workstation (CLI tools, Kubernetes tools, WSL Ansible), and Terraform state security.

### 1. Microsoft Entra ID Tenant & Account Requirements
- **Access Identity:** A user account or Entra ID Service Principal (SPN) with active credentials to sign in via Azure CLI (`az login`).
- **Object ID:** Terraform automatically reads the authenticated identity's `object_id` (`data.azurerm_client_config.current.object_id`) to grant administrative RBAC roles on AKS and Azure Key Vault.
- **Tenant Permissions:**
  - Deploying base infrastructure, monitoring, Sentinel, Azure ML, and playbooks **does not require Global Administrator**; subscription-level RBAC roles are sufficient.
  - *Optional note:* Only granting tenant-wide admin consent for Microsoft Graph API queries or enabling tenant-level connectors (e.g., Entra ID Sign-in/Audit logs in Sentinel) would require *Global Administrator* or *Security Administrator*.

### 2. Azure Subscription Requirements
- **Subscription Type:** A **dedicated lab-only Azure subscription** is strongly recommended (Pay-As-You-Go, Microsoft Azure Sponsorship, Visual Studio Enterprise, or MVP/Partner test subscription).
- **Scope Isolation:** Several lab resources affect the entire subscription:
  - `AzureActivity`: Subscription audit diagnostics export operations across all resource groups in the subscription to `soc-l2-law`.
  - `Microsoft Defender for Servers`: When `enable_defender_for_servers = true`, enabling Plan 1 or Plan 2 applies to **every virtual machine** in the subscription.
  - Key Vault Purge: Permanently purging soft-deleted vaults (`Microsoft.KeyVault/locations/deletedVaults/purge/action`) during `terraform destroy` requires subscription-scoped permissions.

### 3. Required Azure RBAC Roles and Permissions
The identity running Terraform (`az login`) must hold the following roles on the subscription:
- **Primary Role:** `Contributor` on the subscription (subscription scope is required for `AzureActivity` diagnostic settings).
- **Access Management Role:** `User Access Administrator` or `Role Based Access Control Administrator` on the subscription or resource group. This is **mandatory** because Terraform creates RBAC role assignments automatically:
  - Azure ML Compute Instance identity: `Log Analytics Reader` on the workspace.
  - Logic App (Playbook) managed identities: `Microsoft Sentinel Responder`.
  - Sentinel native Service Principal (`Azure Security Insights`): `Microsoft Sentinel Automation Contributor`.
  - Executing operator identity: `Azure Kubernetes Service RBAC Cluster Admin` and `Key Vault Secrets Officer`.
- *Direct Alternative:* **`Owner`** on the subscription encompasses both `Contributor` and `User Access Administrator`.
- **Destroy and Purge Permission:** Running `terraform destroy` and purging Key Vault requires `Microsoft.KeyVault/locations/deletedVaults/purge/action` at the subscription level (included in `Contributor` or `Key Vault Contributor`).

### 4. Azure Resource Providers
Because [providers.tf](providers.tf) sets `resource_provider_registrations = "none"` to prevent runtime registration failures when running with least-privilege accounts, **all required Resource Providers must be registered beforehand** in the subscription.

| Resource Provider | Lab Purpose | Terraform File |
| --- | --- | --- |
| `Microsoft.Compute` | Windows and Linux VMs, AMA and Custom Script extensions | `compute.tf` |
| `Microsoft.Network` | VNet, Subnets, NSGs, Public IPs, Private DNS, Private Endpoint, Load Balancer | `network.tf` |
| `Microsoft.OperationalInsights` | Central Log Analytics Workspace (`soc-l2-law`) | `monitoring.tf` |
| `Microsoft.OperationsManagement` | Monitoring solutions and Container Insights | `main.tf` |
| `Microsoft.SecurityInsights` | Microsoft Sentinel onboarding, analytic rules, and automation rules | `main.tf`, `sentinel.tf` |
| `Microsoft.Insights` | Azure Monitor Agent (AMA), Data Collection Rules (DCR), Application Insights | `monitoring.tf`, `sentinel_notebooks.tf` |
| `Microsoft.Web` | Azure App Service Linux and Logic App API connections | `app_service.tf`, `sentinel_playbooks.tf` |
| `Microsoft.ContainerService` | Azure Kubernetes Service (AKS) cluster | `aks.tf` |
| `Microsoft.ManagedIdentity` | User-assigned managed identities (AKS) | `aks.tf` |
| `Microsoft.KeyVault` | Key, certificate, and secret vaults with Private Endpoint | `key_vault.tf`, `sentinel_notebooks.tf` |
| `Microsoft.Security` | Microsoft Defender for Cloud, Defender for Servers, and WDATP | `defender.tf` |
| `Microsoft.Logic` | Logic Apps workflow engine for automated SOAR response | `sentinel_playbooks.tf` |
| `Microsoft.MachineLearningServices` | Azure ML Workspace and Compute Instance for Jupyter Notebooks | `sentinel_notebooks.tf` |

**PowerShell validation and registration script:**
```powershell
$providers = @(
  "Microsoft.Compute", "Microsoft.Network", "Microsoft.OperationalInsights",
  "Microsoft.OperationsManagement", "Microsoft.SecurityInsights", "Microsoft.Insights",
  "Microsoft.Web", "Microsoft.ContainerService", "Microsoft.ManagedIdentity",
  "Microsoft.KeyVault", "Microsoft.Security", "Microsoft.Logic", "Microsoft.MachineLearningServices"
)
foreach ($p in $providers) {
  $state = (az provider show --namespace $p --query "registrationState" -o tsv 2>$null)
  if ($state -ne "Registered") {
    Write-Host "Registering provider: $p..." -ForegroundColor Yellow
    az provider register --namespace $p --wait
  } else {
    Write-Host "Provider already registered: $p" -ForegroundColor Green
  }
}
```

### 5. Compute Quotas and Regional Capacity Limits
Verify that the target region (`eastus2` by default) has sufficient vCPU quota and SKU availability prior to deployment:
- **`Standard_Dsv6` family:**
  - 2 x `Standard_D2s_v6` VMs = 4 vCPUs.
  - 2 x `Standard_D4s_v6` AKS nodes = 8 vCPUs (plus 4 temporary surge vCPUs during upgrades = up to 12 vCPUs).
  - *Total Dsv6 family:* Minimum **12 to 16 vCPUs** available.
- **`Standard_DSv2` family (for Azure ML):**
  - 1 x `Standard_DS2_v2` Compute Instance = 2 vCPUs.
- **Standard Public IP Addresses:** Minimum **2 to 3 Public IPs** (Ubuntu, Windows, and AKS outbound Load Balancer).
- **Pre-flight checks:**
```powershell
az vm list-usage --location eastus2 -o table
az vm list-skus --location eastus2 --size Standard_D2s_v6 --all -o table
az vm list-skus --location eastus2 --size Standard_D4s_v6 --all -o table
az aks get-versions --location eastus2 -o table
```

### 6. Local Workstation Requirements
The operator machine cloning and running the project requires:
- **Operating System:** Windows 10/11 (with Windows PowerShell 5.1 or PowerShell 7+) or Linux (Ubuntu 22.04+ / Debian / Fedora, if not using the Windows WSL Ansible launcher).
- **Infrastructure Tools:**
  - **Terraform:** `>= 1.7.5` and `< 2.0.0` (tested with v1.9 and v1.10).
  - **Azure CLI (`az`):** `>= 2.60.0`. Signed in via `az login` with target subscription selected via `az account set --subscription "<subscription-id>"`.
  - **Git:** To clone and manage the repository.
- **Kubernetes Tools:**
  - **`kubectl`:** To interact with the AKS cluster.
  - **`kubelogin`:** Required for Entra ID + Azure RBAC authentication against the AKS API server (`kubelogin convert-kubeconfig -l azurecli`).
- **Administrator Network Connectivity:**
  - Obtain the operator's real public IPv4 egress address and set it in `terraform.tfvars`:
    ```hcl
    admin_source_cidr = "203.0.113.45/32" # Replace with your /32 public IP
    ```
  - *Rule:* The Key Vault firewall, VM NSGs, and AKS API server only allow connections originating from this CIDR.

### 7. Ansible Requirements (`enable_ansible = true`)
If automated service configuration (Active Directory, IIS, Apache, and PostgreSQL) is enabled via [ansible.tf](ansible.tf) and [Ansible/](Ansible/README.md):
- **Execution from Windows (via WSL 2):**
  - Requires **WSL 2** with a distribution named `Ubuntu`.
  - Launcher [Invoke-Ansible.ps1](Ansible/Invoke-Ansible.ps1) invokes `wsl -d Ubuntu` to run Python wrapper [run.py](Ansible/run.py) and playbook [site.yml](Ansible/site.yml).
  - Inside WSL Ubuntu:
    - **Python 3.12+** with `venv` and `openssh-client`: `sudo apt-get install -y python3-venv openssh-client`
    - Virtual environment at `~/.venvs/soc-ansible`:
      ```bash
      python3 -m venv ~/.venvs/soc-ansible
      ~/.venvs/soc-ansible/bin/python -m pip install -r Ansible/requirements.txt
      ~/.venvs/soc-ansible/bin/ansible-galaxy collection install -r Ansible/requirements.yml
      ```
    - Required Ansible collections (declared in [Ansible/requirements.yml](Ansible/requirements.yml)): `ansible.windows`, `community.windows`, `microsoft.ad`.
- **Terraform Condition:**
  - `enable_ansible = true` **strictly requires** `create_linux_vm = true` and `create_windows_vm = true`.
- **SSH Connectivity:** WSL must have outbound TCP/22 access to the public IPs of both VMs.

### 8. Azure Machine Learning & Notebook Requirements (`enable_sentinel_notebooks = true`)
- **Infrastructure:** Deploys Azure ML workspace, dedicated Key Vault, Application Insights, and Storage Account (`<prefix>mlsa`).
- **Compute Instance:** Deploys `<prefix>-ci` (`Standard_DS2_v2`).
- **Python Libraries in Azure ML Kernel:**
  - Notebooks ([SOC-L2-Events.ipynb](notebooks/SOC-L2-Events.ipynb), [SOC-L2-Hunting.ipynb](notebooks/SOC-L2-Hunting.ipynb), and [SOC-L2-Log-Analysis.ipynb](notebooks/SOC-L2-Log-Analysis.ipynb)) use `azure-identity`, `azure-monitor-query`, `pandas`, and `matplotlib`.
  - The first code cell runs `%pip install -q azure-identity azure-monitor-query pandas matplotlib` for self-contained setup in the Azure ML Python kernel.
- **Zero-Trust Credentials:** Authentication uses `DefaultAzureCredential()` backed by the Compute Instance's system-assigned managed identity, granted `Log Analytics Reader` on `soc-l2-law`.

### 9. Playbooks & SOAR Requirements (`enable_sentinel_playbooks = true`)
- **Resource Providers:** `Microsoft.Logic` and `Microsoft.Web` registered.
- **API Connections:** After the initial `terraform apply`, open each deployed Logic App (`<prefix>-pb-enrich` and `<prefix>-pb-triage`) in the Azure portal to verify and authorize the `azuresentinel` API connection if needed.

### 10. Terraform State Security Requirements
- **Sensitive Data in `terraform.tfstate`:**
  - Terraform locally generates the SSH private key (`linux_ssh_private_key`), Windows password (`windows_admin_password`), and DSRM password (`dsrm`).
  - All generated credentials are stored **in cleartext inside the state file**. Marking outputs `sensitive` only redacts console output; **it does not encrypt state on disk**.
- **Critical Storage Rules:**
  - **NEVER** store state files in cloud-synced folders such as OneDrive, Dropbox, or Google Drive.
  - **NEVER** commit `.tfstate`, `.tfstate.backup`, `.tfplan`, or `terraform.tfvars` files to Git repositories (verify [.gitignore](.gitignore)).
  - **Recommended Remote Backend:** Configure an Azure Blob Storage backend with encryption at rest, exclusive RBAC authorization, TLS 1.2+, and blob lease locking.

## Lab Costs and Limits

**Unconfirmed budget. No validated cost estimate exists for this subscription.** Before approving deployment, calculate expected runtime hours and regional pricing for:

- Two D2s_v6 VMs, Windows Server license, and Standard managed disks.
- Two D4s_v6 AKS nodes, node OS disks, Standard Load Balancer, outbound public IP, and temporary surge node during upgrades.
- Two static Standard VM public IPs and network egress.
- App Service B1 plan (billed while provisioned, even without a deployed app).
- Key Vault Standard, secret operations, Private Endpoint (hourly + data processed), and Private DNS zone/queries.
- Log Analytics / Microsoft Sentinel ingestion and retention. Azure Activity may qualify for free ingestion tiers; verify against your subscription's pricing model.

The 1 GB daily cap **is not a guaranteed billing ceiling**: overages can occur and the cap does not apply uniformly across all billing categories. Once reached, telemetry ingestion stops until the next reset, creating detection blind spots. Authentication and AKS logs can generate significant volume. `kube-audit-admin` is collected instead of full `kube-audit` to reduce noise; read-only API calls (`get`/`list`) are excluded from that filtered audit stream.

Creating an Azure Cost Management budget and alerts prior to deployment is recommended (not provisioned by this code). Do not assume stopping VMs eliminates all charges: disks, public IPs, App Service plans, AKS nodes, and Private Endpoints continue billing. Always check the AKS managed `MC_` resource group as well.

## Local Usage and Manual Deployment

Run commands from this directory (`Terraform/`). The deployment steps below are instructions for an authorized future execution.

### Offline Validation (No Azure Access Required)

```powershell
terraform init -backend=false -input=false
terraform fmt -check -recursive
terraform validate
terraform test
```

Tests use mock providers and `command = plan`: they require no Azure login and create no cloud resources. They verify SKU profiles, network access rules, agent/DCR associations, single telemetry destination, key generation/wiring, Key Vault network/RBAC controls, direct HTTPS access on App Service, and rejection of unsafe inputs. They do not validate live Azure APIs or actual log ingestion.

### Prepare Inputs

Edit [terraform.tfvars](terraform.tfvars), which explicitly sets all SKUs and sizes: Linux/Windows VMs, OS images and disks, AKS tier/nodes/OS/load balancer, App Service, Key Vault, Log Analytics, and public IPs. Variable defaults remain intact for alternative `.tfvars` files. Image SKUs must belong to the publisher/offer configured in [compute.tf](compute.tf); changing them may replace VMs. Ubuntu on AKS, Standard load balancer, Standard public IPs, and `PerGB2018` workspace SKU are enforced via variable validation. Any other SKU changes require checking compatibility, quota, regional availability, and cost, then reviewing the plan before applying.

Verify the target subscription, authenticated identity, and that `admin_source_cidr` matches the operator's real public egress IP (e.g., `/32`). Legacy variables `aks_admin_object_id` and `linux_ssh_public_key` no longer exist: remove them from any older `.tfvars` files; roles are assigned to the caller and the SSH key pair is generated during deployment.

If a VM already exists with an older SSH key, inspect key changes in the plan and retain existing access until transition completes. TLS key generation stays stable as long as Terraform state is preserved; replacing `tls_private_key` rotates the key pair.

Do not store secrets in a OneDrive-synced directory. **Before running `plan`/`apply`, configure an approved remote backend with encryption, RBAC, state locking, and restricted access**, or run from a protected, non-synced local path. By default Terraform uses local state; this repository neither creates nor assumes a remote backend. Keep `.terraform.lock.hcl`; exclude state files, saved plans, and `.tfvars` from version control.

### Authenticate, Plan, and Review

Once your backend is ready and budget/permissions are confirmed:

```powershell
az login
az account set --subscription "<subscription-id>"
terraform init
terraform validate
if ($LASTEXITCODE -ne 0) { throw "terraform validate failed" }
terraform plan -out=lab.tfplan
if ($LASTEXITCODE -ne 0) { throw "terraform plan failed" }
```

Inspect the plan carefully and explicitly approve expected costs and resource changes. Saved `.tfplan` files contain sensitive values; protect them and delete them after use. Only then apply manually:

```powershell
terraform apply .\lab.tfplan
terraform output
```

Never use `-auto-approve`. For AKS access, install `kubectl` and `kubelogin`, authenticate as the authorized identity, and fetch user credentials:

```powershell
az aks get-credentials --resource-group "<prefix>-rg" --name "<prefix>-aks"
kubelogin convert-kubeconfig -l azurecli
kubectl get nodes
```

Kubeconfigs, passwords, and workspace shared keys are not exported as outputs. The generated SSH private key has a dedicated sensitive output: `linux_ssh_private_key`. To connect via SSH, export it with `terraform output -raw linux_ssh_private_key` exclusively to a protected file outside OneDrive—never paste it into chats, logs, or repositories—and restrict file ACLs to your user account. It cannot be retrieved from Key Vault because Key Vault stores only the public key. Mock tests do not generate real keys.

## Key Vault Operations

- The Windows password is no longer an input variable: remove `windows_admin_password` from older `.tfvars` files and unset `TF_VAR_windows_admin_password`. It is generated on `apply` and remains stable unless `random_password.windows_admin` is replaced. Neither `timestamp()` nor automatic per-apply rotation is used.
- For RDP access, retrieve `windows-admin-password` from Key Vault using an authorized identity from the allowed network, preferably via the Azure portal without copying it into logs or files. Terraform exports only `windows_admin_password_secret_id`, never the password value.
- If migrating an existing VM, the first plan will update its password; review and approve the change. Do not rotate the Key Vault secret independently: to rotate later, plan a replacement of `random_password.windows_admin` so both the VM and secret update together. Updating a Key Vault secret alone does not change the guest OS password. If `apply` fails midway, check which resources succeeded and reconcile the VM and vault before attempting RDP.
- The identity running Terraform receives `Key Vault Secrets Officer` scoped strictly to this vault to create and manage secrets. It is the same caller identity granted AKS cluster admin RBAC, avoiding manual Object ID inputs. Network CIDR rules authorize network reachability, **not identity**. Other operators require explicit data-plane RBAC roles; VMs are not granted secret access automatically.
- Run `plan`/`apply`/`refresh`/`destroy` from `admin_source_cidr` or from a network with Private Endpoint connectivity and Private DNS resolution. CI runners on other public IPs will be blocked by the vault firewall. Control-plane ARM access does not grant secret data-plane access.
- Newly created RBAC assignments take time to propagate. If Azure returns `403`, inspect the error code: `ForbiddenByFirewall` indicates a source IP / DNS mismatch; RBAC denial indicates identity/role propagation delay. Retry once confirmed rather than opening the firewall or adding blind sleeps.
- Query only the public SSH key post-deployment if needed: `az keyvault secret show --vault-name "<prefix>-kv01" --name linux-ssh-public-key --query value -o tsv` (or via output `key_vault_name`). From inside the VNet, `Resolve-DnsName "<prefix>-kv01.vault.azure.net"` resolves to `key_vault_private_ip`. No admin VPN is provisioned.
- Vault name `${name_prefix}-${key_vault_name_suffix}` (`kv01` by default) must be globally unique and satisfy Azure Key Vault naming rules (including no consecutive hyphens); adjust `name_prefix` or `key_vault_name_suffix` on collision.
- 7-day soft delete is enabled, while **purge protection is intentionally disabled**: `terraform destroy` purges secrets and the vault immediately, releasing the name. Once enabled on a vault, purge protection cannot be disabled (*once Purge Protection has been Enabled it's not possible to disable it*).
- **Migration from earlier deployments:** the earliest version created `<prefix>-kv` with purge protection enabled. Switching to `<prefix>-kv01` causes the next `apply` to **replace** it: creating a new vault without purge protection, rewriting secrets, Private Endpoint, role assignment, and diagnostics, and deleting the old vault (which Azure purges after the 7-day retention period). Review that replacement in the plan before applying.
- Vault audit events flow to the shared Sentinel workspace: query `AZKVAuditLogs | where TimeGenerated > ago(30m)`. Verify actual generation and ingestion after deployment.

## Post-Deployment Operational Verification

> Automated benign activity: [Invoke-SocLabLogGeneration.ps1](scripts/Invoke-SocLabLogGeneration.ps1) executes tests P02–P15 from the [Sentinel coverage guide](docs/Sentinel-Coverage-and-Testing.md). Terraform triggers it at the end of `apply` when `enable_log_generation = true` ([details](#log-generation-at-the-end-of-deployment)), or you can run it manually. Pass `-WhatIf` to preview scope without generating activity.

1. Confirm both AMA extensions show `Succeeded` and verify each DCR association. On Ubuntu, check `cloud-init status --wait` and `systemctl status rsyslog`.
2. Perform normal authorized administrative logins to each VM. Certain Windows events (such as 4688) require guest audit policy configuration; listing an Event ID in a DCR XPath query neither enables guest auditing nor installs Sysmon.
3. Access the App Service HTTPS endpoint. Without a deployed app, no application logs are expected and console logs may remain empty. Provisioning the endpoint does not deploy web application code.
4. Check AKS nodes and monitoring pods. Without user workloads, `ContainerLogV2` depends on containers writing to stdout/stderr and agent filtering settings. Pod inventory and events collect at 5-minute intervals.
5. Open Sentinel Logs and, after allowing for ingestion latency, run each query independently:

```kusto
Heartbeat
| where TimeGenerated > ago(30m)
| summarize Latest=max(TimeGenerated) by Computer, OSType
```

```kusto
Syslog
| where TimeGenerated > ago(30m)
| summarize Events=count(), Latest=max(TimeGenerated) by Computer, Facility
```

```kusto
SecurityEvent
| where TimeGenerated > ago(30m)
| summarize Events=count() by Computer, EventID
```

```kusto
Event
| where TimeGenerated > ago(30m)
| summarize Events=count() by Computer, EventLog
```

```kusto
AppServiceHTTPLogs
| where TimeGenerated > ago(30m)
| summarize Requests=count() by _ResourceId
```

```kusto
KubePodInventory
| where TimeGenerated > ago(30m)
| summarize Latest=max(TimeGenerated) by ClusterName, Namespace
```

```kusto
ContainerLogV2
| where TimeGenerated > ago(30m)
| summarize Records=count() by PodNamespace, PodName
```

```kusto
AKSAuditAdmin
| where TimeGenerated > ago(30m)
| summarize Operations=count() by _ResourceId
```

```kusto
AKSControlPlane
| where TimeGenerated > ago(30m)
| summarize Records=count() by Category
```

```kusto
AzureActivity
| where TimeGenerated > ago(1h)
| summarize Operations=count() by CategoryValue, ResourceGroup
```

Custom/dedicated tables may not exist until the first record is ingested; an empty result or missing-table error **does not confirm** healthy integration. Check event generation, network egress, managed identity, DCR associations, diagnostic settings, daily cap, and ingestion latency. Base Sentinel onboarding alone creates no detections unless `enable_sentinel_analytics` or custom rules are enabled.

### Removal of Application Gateway and WAF

By user decision, the stack no longer includes Application Gateway, WAF policy, dedicated gateway subnet, NSG, public IP, or WAF diagnostics. App Service uses direct public HTTPS access without WAF protection; SCM/Kudu no longer inherits restrictions from the removed subnet. Minimum TLS 1.2 and disabled basic publishing authentication remain enforced.

If those resources were previously deployed and remain in Terraform state, generate and inspect a fresh plan: Terraform will propose destroying them and updating App Service access restrictions. Do not run `terraform destroy` (which destroys the entire lab) or manually manipulate state. Use output `app_service_url` as the endpoint, and discard stale saved plans.

### Container Insights: Empty Add-on Identity

With `msi_auth_for_monitoring_enabled = true`, Azure may return `oms_agent_identity = []`. Do not index into that list or assign `Monitoring Metrics Publisher` to the add-on: [Container Insights managed identity authentication](https://learn.microsoft.com/azure/azure-monitor/containers/container-insights-authentication) does not use that role. The add-on uses the configured workspace and explicit DCR association (`target_resource_id` referencing the cluster).

If a prior `apply` failed with `Invalid index` on `aks_monitor`, generate a fresh plan and review before applying; never reuse an old saved plan. Recreating the cluster or disabling monitoring is unnecessary.

## Teardown

Only after explicit authorization and preserving any required investigation evidence:

```powershell
terraform plan -destroy -out=destroy.tfplan
terraform apply .\destroy.tfplan
```

Destroy plans still require mandatory input variables; passwords are not entered manually.

Destruction is **permanent** due to the `features` configuration in [providers.tf](providers.tf):

| Resource | Behavior on `destroy` |
|---|---|
| Key Vault secrets | Deleted and purged (`purge_soft_deleted_secrets_on_destroy`). |
| Key Vault | Deleted and purged (`purge_soft_delete_on_destroy`); requires `purge_protection_enabled = false`. |
| Log Analytics Workspace & Sentinel | Permanently deleted without the 14-day recovery window (`permanently_delete_on_destroy`); all data is lost. |
| VM OS Disks | Deleted alongside VMs (`delete_os_disk_on_deletion`). |
| AKS (including `MC_` group), App Service, VNet, IPs, Private DNS, DCRs, diagnostics, roles, and SSH key | Deleted immediately (no soft delete). |

`recover_soft_deleted_*` is disabled: if a soft-deleted vault or secret with the same name exists, `apply` fails rather than silently recovering it. Requirements for clean purge during destroy:

- The identity running Terraform requires `Microsoft.KeyVault/locations/deletedVaults/purge/action` at **subscription** scope (e.g., `Contributor` or `Key Vault Contributor`); resource-group scope alone is insufficient. Secret purge is covered by `Key Vault Secrets Officer`, which Terraform destroys after purging secrets.
- Run `destroy` from `admin_source_cidr` or the private network because secret purge is a data-plane operation.
- Note that `prevent_deletion_if_contains_resources = false` is configured on the provider's `resource_group` feature block so unmanaged portal artifacts inside the lab group do not block teardown; verify group contents before destroying. Subscription-level diagnostic settings created by this stack are removed without touching third-party diagnostics. Securely delete saved `.tfplan` files afterward.

## Verified Design References

- [AzureRM 5.10: AKS](https://registry.terraform.io/providers/hashicorp/azurerm/5.10.0/docs/resources/kubernetes_cluster).
- [AzureRM 5.10: DCR](https://registry.terraform.io/providers/hashicorp/azurerm/5.10.0/docs/resources/monitor_data_collection_rule).
- [AzureRM: Sentinel onboarding](https://registry.terraform.io/providers/hashicorp/azurerm/5.10.0/docs/resources/sentinel_log_analytics_workspace_onboarding).
- [AKS system node pool requirements](https://learn.microsoft.com/azure/aks/use-system-pools).
- [Enable AKS monitoring](https://learn.microsoft.com/azure/azure-monitor/containers/kubernetes-monitoring-enable).
- [Official Container Insights MSI + DCR Terraform example](https://github.com/microsoft/Docker-Provider/blob/ci_prod/scripts/onboarding/aks/onboarding-msi-terraform/main.tf).
- [Log Analytics daily cap](https://learn.microsoft.com/azure/azure-monitor/logs/daily-cap).
- [Azure Pricing Calculator](https://azure.microsoft.com/pricing/calculator/).
- [AzureRM: SSH public key](https://registry.terraform.io/providers/hashicorp/azurerm/5.10.0/docs/resources/ssh_public_key).
- [TLS: private key generation and state persistence](https://registry.terraform.io/providers/hashicorp/tls/4.4.2/docs/resources/private_key).
- [Random: generated password and state persistence](https://registry.terraform.io/providers/hashicorp/random/3.9.1/docs/resources/password).
- [Azure Key Vault: Private Link](https://learn.microsoft.com/azure/key-vault/general/private-link-service).
- [AKS supported diagnostic log categories, including guard](https://learn.microsoft.com/azure/azure-monitor/reference/supported-logs/microsoft-containerservice-managedclusters-logs).
- [Command-line process auditing and Event 4688 exposure](https://learn.microsoft.com/windows-server/identity/ad-ds/manage/component-updates/command-line-process-auditing).
- [auditpol: subcategory selection by GUID and permissions](https://learn.microsoft.com/windows-server/administration/windows-commands/auditpol-set).

## License and Community

This project is distributed under the **GNU General Public License v3.0 (GPLv3)**. See [LICENSE](LICENSE) for full rights and terms.

- [Contributing Guide](CONTRIBUTING.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)
- [Security Policy & Vulnerability Reporting](SECURITY.md)
- [Support & Help Channels](SUPPORT.md)
- [Changelog](CHANGELOG.md)
