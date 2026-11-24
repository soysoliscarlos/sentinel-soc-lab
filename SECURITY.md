**English** | [Español](SECURITY.es.md)

# Security Policy

Security is at the core of this SOC L2 Cyber Range project. We take the protection of configurations, cloud infrastructure, and data across user and lab environments seriously.

---

## Supported Versions

Currently, only the active default branch (`main` / `master`) and the latest release receive security reviews and patches:

| Version | Supported |
| :--- | :--- |
| `main` branch (current source) | :white_check_mark: Yes |
| Older versions / feature branches | :x: No |

---

## Reporting a Vulnerability

**PLEASE DO NOT REPORT SECURITY VULNERABILITIES VIA PUBLIC GITHUB ISSUES.**

If you identify a security vulnerability (for example: unintended credential exposure, risky default network rules, script command injection, or excessive Azure RBAC privilege escalation):

1. **Use GitHub Private Vulnerability Reporting** (if enabled on this repository):
   - Go to the repository's **Security** tab.
   - Click **Report a vulnerability** to open a confidential advisory.
2. **Or contact the project maintainer privately** using the contact channels listed on the maintainer's GitHub profile.

### Helpful Information to Include:
- Detailed description of the vulnerability or misconfiguration.
- Exact steps or Terraform / KQL / script snippet to reproduce the issue.
- Potential impact scenario (e.g., privilege escalation, public exposure of lab resources, secret leakage).
- Suggested mitigation or patch (if available).

---

## Response Commitment

- **Initial acknowledgment:** Within 48 to 72 business hours.
- **Assessment and remediation:** Severity will be evaluated and a fix coordinated via a private advisory branch or security patch.
- **Public disclosure:** Published once the fix is released so users can update safely.

---

## Recommended Security Practices for Lab Operators

1. **Never commit real credentials or state**: Never commit `terraform.tfstate`, `.tfplan`, `*.tfvars` with real values, SSH private keys, or service passwords to version control, and never store state inside cloud-synced folders (OneDrive, Dropbox, Google Drive).
2. **Restrict NSG and firewall source CIDRs**: Always scope `admin_source_cidr` in `terraform.tfvars` (enforced by [variables.tf](variables.tf) and [network.tf](network.tf)) to your `/32` public IPv4 egress address—never open management ports to `0.0.0.0/0`.
3. **Tear down resources when finished**: Run `terraform destroy` (or stop compute instances such as Azure ML) after workshops to prevent unintended cloud charges and unnecessary attack surface exposure.
