**English** | [Español](CONTRIBUTING.es.md)

# Contributing Guide

Thank you for your interest in contributing to this Azure SOC L2 Cyber Range with Terraform! This document defines the guidelines and workflow for collaborating on the project in an orderly, secure, and consistent way.

---

## Code of Conduct

By participating in this project, you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md). Please treat all community members with respect and empathy.

---

## How Can I Contribute?

You can contribute in several ways:
1. **Report bugs**: If you find a syntax error, resource discrepancy, or unexpected behavior.
2. **Propose enhancements (Feature Requests)**: Suggestions for new Sentinel analytic rules, notebook integrations, playbooks, or telemetry configurations.
3. **Improve documentation**: Fix typos, add explanatory diagrams, step-by-step guides, or KQL query examples (keeping English `.md` and Spanish `.es.md` mirrors in sync).
4. **Submit code or playbooks**: Propose changes to Terraform templates or Ansible automation.

---

## Pull Request (PR) Workflow

1. **Fork** the repository to your GitHub account.
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/<your-username>/<repository>.git
   cd Terraform
   ```
3. **Create a descriptive branch** for your change:
   ```bash
   git checkout -b feat/new-sentinel-rule
   # or
   git checkout -b fix/rdp-nsg-rule
   ```
4. **Make your changes** following the style and security guidelines below.
5. **Validate your Terraform code** locally:
   ```bash
   # 1. Check formatting
   terraform fmt -check -recursive

   # 2. Initialize without remote backend
   terraform init -backend=false

   # 3. Validate syntax and references
   terraform validate

   # 4. Run mock-provider tests
   terraform test
   ```
6. **Commit your changes** with clear messages ([Conventional Commits](https://www.conventionalcommits.org/) recommended):
   ```bash
   git commit -m "feat(sentinel): add analytic rule for RDP brute-force detection"
   ```
7. **Push your branch and open a Pull Request**:
   - Describe what problem it solves or what capability it adds.
   - Link the corresponding Issue if applicable (`Closes #123`).
   - Complete the checklist provided in the PR template.

---

## Code Guidelines and Terraform Standards

### 1. Formatting, Naming, and Language
- Always run `terraform fmt -recursive` before submitting changes.
- Use `snake_case` for resource names, variables, and outputs (e.g., `windows_vm_size`, `enable_sentinel_analytics`).
- Write all code comments, variable `description`s, output `description`s, and test messages in **English**.
- Document all variables (`description`, `type`, and `default` when applicable) in [variables.tf](variables.tf) (or their feature `.tf` file) and outputs in [outputs.tf](outputs.tf).
- When updating Markdown documentation, update both the primary English `.md` file and its `.es.md` Spanish counterpart.

### 2. Security and Secret Hygiene (CRITICAL)
- **NEVER** commit secrets, passwords, API keys, private keys, certificates, `.tfplan`, or `terraform.tfstate` files.
- **NEVER** commit `terraform.tfvars` files containing real environment values. Use [terraform.tfvars.example](terraform.tfvars.example) to illustrate structure with safe placeholders.
- Check [.gitignore](.gitignore) to verify no sensitive files are tracked by Git.
- If you spot an accidental credential leak, report it privately right away following [SECURITY.md](SECURITY.md).

### 3. Architectural Responsibilities
- Keep cloud infrastructure, identities, diagnostics, DCRs, and Sentinel resources in Terraform.
- Post-deployment guest OS service configurations (e.g., IIS/Apache, AD DS, PostgreSQL) belong in [Ansible/](Ansible/README.md).

---

## Contribution License

By contributing to this repository, you agree that your code and documentation contributions will be distributed under the terms of the **GNU General Public License v3.0 (GPLv3)**. See [LICENSE](LICENSE) for details.
