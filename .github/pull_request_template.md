## Change Description

Briefly describe the changes introduced in this Pull Request and the motivation behind them.

Linked Issue (if applicable): Closes #

---

## Type of Change

Mark the applicable options with an `x`:

- [ ] **Bug fix**: Fixes an issue without breaking backward compatibility.
- [ ] **New feature**: Adds new Azure resources, Sentinel rules, notebooks, playbooks, or telemetry.
- [ ] **Enhancement / Refactor**: Improves code structure without altering functional behavior.
- [ ] **Documentation update**: Updates Markdown guides, diagrams, or comments (keep `.md` and `.es.md` mirrors in sync).
- [ ] **Breaking change**: Requires recreating state or updating existing input variables.

---

## Affected Components

- [ ] Microsoft Sentinel (Analytic rules, Hunting queries, Playbooks, Workbooks, Notebooks)
- [ ] Compute (Windows / Linux Virtual Machines)
- [ ] Networking & Security (VNet, Subnets, NSG, Key Vault, Defender)
- [ ] Containers / App Services (AKS, App Service)
- [ ] Telemetry & Guest Configuration (AMA, DCR, Ansible, Log generation scripts)
- [ ] Documentation & Configuration templates

---

## Quality & Security Checklist

Before submitting this PR, confirm that you have completed the following checks:

- [ ] My code follows the guidelines in [CONTRIBUTING.md](../CONTRIBUTING.md), with all code, comments, and descriptions in English.
- [ ] I ran `terraform fmt -check -recursive` and formatting matches Terraform conventions.
- [ ] I ran `terraform validate` and `terraform test` and all checks pass.
- [ ] **Security**: I verified that I have **NOT** included real credentials, passwords, SSH private keys, `.tfstate`/`.tfplan` files, or `.tfvars` with secrets in this PR.
- [ ] I updated relevant documentation (both English `.md` and Spanish `.es.md` mirrors, plus descriptions in [variables.tf](../variables.tf)/[outputs.tf](../outputs.tf)) if required by my changes.
- [ ] I understand and agree that my contributions are licensed under **GNU GPLv3**.
