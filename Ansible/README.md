**English** | [Español](README.es.md)

# Lab Configuration with Ansible

## Confirmed Scope and Status

Implementation prepared to **be executed by Terraform**, not yet deployed or tested against live VMs. Both existing VMs are reused; no extra compute is provisioned.

`enable_ansible = true` requires `create_linux_vm = true` and `create_windows_vm = true`. Terraform rejects any combination missing a VM; partial Ansible runs are not supported. To omit one or both VMs, set `enable_ansible = false` in [your Terraform inputs](../terraform.tfvars).

Local validation completed on 2026-10-22, including the expanded logging configuration: formatting and `terraform validate` passed, **mock-provider Terraform tests**, **8 Python unit tests** (including live `rsyslog` syntax validation when installed), PowerShell launcher and Windows service-logging tests on Windows PowerShell 5.1, and playbook syntax validation with Ansible Core 2.20.10. Local validation does not prove live installation, connectivity, or log ingestion.

| Target | Configuration |
| --- | --- |
| Ubuntu 22.04 | Apache (`apache2`) and PostgreSQL from Ubuntu repositories; auto-start, local HTTP, and `pg_isready` verified during execution |
| Windows Server 2022 | IIS, AD DS, and DNS; new forest `lab.example.test`, NetBIOS `LAB`; local HTTP, domain, services, and SRV record verified |

Running IIS on a Domain Controller is an **explicit lab-only exception**, not a recommended production architecture. No client machines are joined to the domain, no extra PostgreSQL databases/applications/users are created, and no attack simulations are deployed here. PostgreSQL listens exclusively on `localhost` using Ubuntu's default local authentication.

## Responsibilities and Access

- [Terraform](../ansible.tf) prepares networking, static private IP `10.20.1.10` for Windows, uncached Windows OS disk, DSRM secret, and Windows OpenSSH via the existing auditing Custom Script Extension. It preserves the Windows audit script and appends the SSH bootstrap only when Ansible is enabled; the combined payload is gzip-compressed to stay below `cmd.exe`'s 8,191-character limit. Static IP is never hardcoded inside the guest OS: Azure manages it via DHCP reservation.
- NSGs allow Windows SSH and HTTP on both VMs **only from `admin_source_cidr`**, preserving existing Linux SSH and Windows RDP rules. WinRM, PostgreSQL, and AD ports remain closed. VNet DNS settings are not switched to point to this DC.
- The Windows extension installs OpenSSH Server, sets Windows PowerShell as default shell, authorizes the generated Linux SSH public key for administrators, and disables SSH password authentication. It scopes the Windows Firewall SSH rule to `admin_source_cidr`. Outbound access to Windows Features on Demand sources is required.
- [The PowerShell launcher](Invoke-Ansible.ps1) retrieves SSH host public keys via Azure Run Command against the explicit subscription. It never uses `ssh-keyscan` or disables `StrictHostKeyChecking`.
- [The Linux runner](run.py) creates temporary SSH keys and inventory outside the workspace (`/tmp` with `0700` directory and `0600` key permissions), runs [site.yml](site.yml), propagates exit codes, and removes temporary files on normal exit or exception. A hard OS crash could prevent cleanup.
- Ansible configures guest services. On Windows it escalates via `runas` as `SYSTEM` so local AD operations do not depend on SSH credential delegation. AD modules redact the DSRM password from task output.
- After installing and verifying each service, Ansible configures its logs. The Linux and Windows DCRs depend on `terraform_data.ansible` completion so new log sources are added only after files and event channels exist. No duplicate agents, DCRs, or workspaces are created.

NSGs continue blocking AD client traffic, even inside the VNet. Enabling domain-joined clients, remote PostgreSQL access, HTTPS certificates, or HTTP from additional sources requires separate design and authorization. Generic `Any/Any` rules are never used.

## Prerequisites Before Applying

1. Run Terraform from **Windows PowerShell**, with an authenticated Azure CLI session and a WSL 2 distribution named `Ubuntu`. This launcher does not target native Linux Terraform hosts or CI agents without WSL.
2. Inside WSL: **Python 3.12+**, `openssh-client`, virtual environment `~/.venvs/soc-ansible`, and installed Python packages and Ansible collections. Dependencies are not auto-installed during `terraform apply`.
3. Network reachability from WSL to both VM public IPs on TCP/22. `admin_source_cidr` must match WSL's actual public egress IP; check VPNs and proxies.
4. Standard Terraform permissions (including NIC, NSG, and VM extension updates) plus `Microsoft.Compute/virtualMachines/runCommand/action` on both VMs to fetch host keys. Azure CLI and the Terraform provider must target the same subscription. The SSH key grants administrative access and passwordless `sudo` on Ubuntu.
5. Confirm `10.20.1.10` is free. Changing private IP allocation and disk caching may briefly interrupt Windows; role installation and DC promotion can reboot Windows multiple times.
6. Retain recovery RDP access. Local account `socadmin` becomes a domain account upon promotion; sign in as `LAB\socadmin` for RDP afterward. Do not rotate the DSRM password by editing Key Vault alone: updating the secret does not update DSRM on an existing DC.
7. Protect state and saved plans outside OneDrive, ideally in an approved remote backend. Alongside the SSH private key and admin password, state stores the generated DSRM password, which is also written to `windows-dsrm-password` in the lab Key Vault for recovery. It is never exposed as an output or written to persistent inventory files.
8. Permissions to update `Microsoft.Insights/dataCollectionRules` and their workspace associations, outbound AMA connectivity to Azure Monitor, and workspace query permissions for post-deployment verification. No inbound Syslog ports are opened: both Linux sources are local.

Baseline Azure compute charges apply, while increased log volume may raise disk usage and Log Analytics ingestion/retention costs. **Full SQL statement logging (`log_statement='all'`) was explicitly authorized by the user.** Queries may contain passwords, personal data, or sensitive values, and web access logs capture usernames, IPs, and URL query strings. Restrict workspace access and use synthetic lab data only. Remember that the 1 GB/day cap is not a hard billing limit and halts ingestion once reached.

### Prepare the Control Node

In an **Ubuntu WSL** terminal, from `Terraform/Ansible`:

```bash
sudo apt-get update
sudo apt-get install -y python3-venv openssh-client
python3 -m venv ~/.venvs/soc-ansible
~/.venvs/soc-ansible/bin/python -m pip install -r requirements.txt
~/.venvs/soc-ansible/bin/ansible-galaxy collection install -r requirements.yml
```

If `sudo` is unavailable and `openssh-client` is already installed (`ssh -V`), create the virtual environment without `ensurepip`:

```bash
python3 -m venv --without-pip ~/.venvs/soc-ansible
curl -fsSL https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py
~/.venvs/soc-ansible/bin/python /tmp/get-pip.py && rm -f /tmp/get-pip.py
~/.venvs/soc-ansible/bin/python -m pip install -r requirements.txt
~/.venvs/soc-ansible/bin/ansible-galaxy collection install -r requirements.yml
```

Uses Ansible Core 2.20 and collections pinned in [requirements.yml](requirements.yml). Windows SSH connections are officially supported in Ansible 2.18+ with the inbox OpenSSH Server on Windows Server 2022+.

### Offline Validation (No Azure Access Required)

From `Terraform/` in PowerShell:

```powershell
terraform fmt -check -recursive
terraform validate
terraform test
.\Ansible\tests\Test-Launcher.ps1
.\Ansible\tests\Test-ServiceLogging.ps1
```

From `Terraform/Ansible` in WSL:

```bash
PYTHONDONTWRITEBYTECODE=1 ~/.venvs/soc-ansible/bin/python -m unittest discover -s tests -v
~/.venvs/soc-ansible/bin/ansible-playbook --syntax-check -i localhost, site.yml
```

Minimal inventory syntax checks emit warnings about missing `linux` and `windows` groups without connecting or executing tasks. Launcher tests validate generated inventory structure, file permissions, strict host key checking, cleanup, and error propagation. PowerShell tests mock Azure CLI, WSL, IIS, and `auditpol` locally to verify JSON transport, idempotency, check mode, and failure handling without remote execution. The `rsyslog` test runs `rsyslogd -N1` when available on the control node (otherwise skipped). Terraform tests run mock-provider plans with `enable_ansible = false` by default unless overridden per test block.

### Enable and Run via Terraform

In your protected `.tfvars` file, set:

```hcl
enable_ansible = true
```

From `Terraform/` in Windows PowerShell, after confirming budget, permissions, and backend:

```powershell
terraform plan -out=lab-ansible.tfplan
if ($LASTEXITCODE -ne 0) { throw "terraform plan failed" }
# Review and approve the plan before continuing.
terraform apply .\lab-ansible.tfplan
if ($LASTEXITCODE -ne 0) { throw "Lab configuration failed" }
```

`apply` runs Ansible after VMs, AMA extensions, Windows SSH bootstrap, and the DSRM secret are provisioned, then updates the Linux and Windows DCRs. Inspect the full plan carefully—it may include other pending stack changes. Because sensitive environment variables are passed to `local-exec`, Terraform may redact provisioner output; any non-zero launcher exit fails `apply` explicitly.

Ansible re-runs whenever tracked automation files, target metadata, or credentials in `triggers_replace` change. It does not use `timestamp()` or re-run unnecessarily on no-op applies. Terraform does not detect manual guest OS drift; to force a deliberate re-converge:

```powershell
terraform plan '-replace=terraform_data.ansible[0]' -out=lab-ansible.tfplan
# Review before applying.
terraform apply .\lab-ansible.tfplan
```

After applying, verify HTTP reachability on both public IPs from `admin_source_cidr` and run a second authorized `apply` if you wish to confirm idempotency on live VMs.

### Hash Mismatch Error: `filesha256` Returned an Inconsistent Result

Terraform requires tracked files in `local.ansible_files` to remain byte-identical throughout planning and apply. If an editor, background formatter, or cloud sync modifies a file mid-run, Terraform aborts with `function returned an inconsistent result`.

Wait for edits and file sync to settle, discard the stale saved plan, and create a fresh plan:

```powershell
terraform plan -out=lab-ansible-retry.tfplan
if ($LASTEXITCODE -ne 0) { throw "New plan failed" }
# Review the full plan; do not edit files until apply finishes.
terraform apply .\lab-ansible-retry.tfplan
if ($LASTEXITCODE -ne 0) { throw "Retry apply failed" }
```

Protect saved plans just like state files, and prefer running outside cloud-synced folders. Never delete state, add `ignore_changes`, or replace file hashes with `timestamp()` to work around the check.

**Do not set `enable_ansible = false` expecting an automated uninstall.** Disabling the variable removes helper resources/secrets, restores dynamic private IP and disk cache settings, and closes added NSG rules, **but does not demote Active Directory or uninstall IIS, Apache, PostgreSQL, or OpenSSH**. Domain controller demotion and data removal require a dedicated administrative procedure.

## Telemetry and References

The logging configuration below is prepared when `enable_ansible = true` (enabled in the lab inputs). Variable `enable_ansible` defaults to `false` for standalone inputs. Analytic rules are managed separately via `enable_sentinel_analytics`.

| Service | Log Generation and Collection Path | Log Analytics Table |
| --- | --- | --- |
| IIS | W3C enabled, local files under `C:\inetpub\logs\LogFiles\W3SVC1`, hourly UTC rollover; native AMA IIS log source | `W3CIISLog` (includes HTTP error status codes; distinct from Failed Request Tracing) |
| AD DS | Success/failure auditing for user, computer, security group, Kerberos, NTLM credential validation, and Directory Service Changes; Event IDs added to existing Security DCR stream | `SecurityEvent` |
| AD DS, DNS, and replication | Enabled channels `Directory Service`, `DNS Server`, `DFS Replication` (Critical/Error/Warning); System/Application retained | `Event` |
| Apache | Default site combined `access.log` and `error.log`; rsyslog `imfile`, facility `local6`, tags `apache-access` and `apache-error` | `Syslog` |
| PostgreSQL | `stderr,syslog`, facility `LOCAL5`, identifier `postgres-soc`, connections/disconnections, errors, and `log_statement='all'` | `Syslog` |

[Linux logging tasks](linux-logging.yml) validate Apache, `rsyslog`, and `pg_file_settings` before flushing handlers, then verify active PostgreSQL settings. Local `stderr` and file logs remain intact. Apache reloads and PostgreSQL/`rsyslog` restart on configuration changes. [The Windows script](files/Configure-ServiceLogging.ps1) configures IIS and audit subcategories post-promotion using language-independent GUIDs and numeric `auditpol /backup` values, cleaning up temporary CSV exports in a `finally` block.

### Coverage Limitations

- **Directory Service Changes does not configure object SACLs.** Events 5136/5137/etc. only fire when target AD objects have matching SACLs. Full LDAP modification or debug DNS/LDAP logging is not claimed.
- **`log_statement='all'` is not `pgAudit`** or infallible transactional auditing: statements failing parse/bind before execution are not logged as normal statements, though `log_min_error_statement=error` captures error-triggering queries.
- **Syslog message splitting:** long SQL queries may split across multiple Syslog records (`syslog_split_messages = on`); sequence numbers and PIDs are preserved, so **one table row does not always equal one SQL query**. Pipeline size limits and throttling can still drop messages.
- **Apache severity mapping:** `imfile` tags access entries as `info` and error log lines as `error` while preserving original text severity inside the message. Interrupted `imfile` state files may replay lines; PostgreSQL local files are not double-ingested via `imfile`.
- **IIS site ID:** expects `Default Web Site` with `id = 1` (`W3SVC1`) and fails explicitly otherwise. No automated IIS log retention/deletion task is installed—monitor disk usage. IIS log delivery can wait until the next hourly file rollover or flush.
- Workspace retention and daily quota remain unchanged. Empty tables without fresh traffic do not indicate failure.

### Post-Apply Verification Queries

Generate normal benign activity with synthetic data, confirm local log files/events exist, and query using **each VM's exact `_ResourceId`** in `soc-l2-law`:

```kusto
W3CIISLog
| where TimeGenerated > ago(2h)
| where _ResourceId =~ "<windows-vm-resource-id>"
| summarize Records=count(), Latest=max(TimeGenerated) by Computer
```

```kusto
SecurityEvent
| where TimeGenerated > ago(2h)
| where _ResourceId =~ "<windows-vm-resource-id>"
| where EventID in (4720, 4728, 4738, 4742, 4768, 4769, 4771, 4776, 5136)
| summarize Records=count(), Latest=max(TimeGenerated) by Computer, EventID
```

```kusto
Event
| where TimeGenerated > ago(2h)
| where _ResourceId =~ "<windows-vm-resource-id>"
| where EventLog in ("Directory Service", "DNS Server", "DFS Replication")
| summarize Records=count(), Latest=max(TimeGenerated) by Computer, EventLog
```

```kusto
Syslog
| where TimeGenerated > ago(2h)
| where _ResourceId =~ "<linux-vm-resource-id>"
| where (Facility == "local6" and ProcessName in ("apache-access", "apache-error"))
    or (Facility == "local5" and ProcessName == "postgres-soc")
| summarize Records=count(), Latest=max(TimeGenerated) by Computer, Facility, ProcessName
```

Zero AD DS service channel events can be normal when no warnings or errors occur. Verify security auditing with authorized administrative actions; see also the [Sentinel coverage and testing guide](../docs/Sentinel-Coverage-and-Testing.md).

- [Windows SSH in Ansible](https://docs.ansible.com/ansible/latest/os_guide/windows_ssh.html).
- [Domain creation with `microsoft.ad.domain`](https://docs.ansible.com/ansible/latest/collections/microsoft/ad/domain_module.html).
- [OpenSSH Server configuration for Windows](https://learn.microsoft.com/windows-server/administration/openssh/openssh-server-configuration).
- [Collect IIS logs with AMA](https://learn.microsoft.com/azure/azure-monitor/vm/data-collection-iis).
- [Collect Syslog with AMA](https://learn.microsoft.com/azure/azure-monitor/vm/data-collection-syslog).
- [Advanced security audit policy settings for AD DS](https://learn.microsoft.com/windows-server/identity/ad-ds/plan/security-best-practices/advanced-audit-policy-configuration).
- [PostgreSQL 14 error reporting and logging](https://www.postgresql.org/docs/14/runtime-config-logging.html).
