**English** | [Español](CHANGELOG.es.md)

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Changed
- Standardized the entire repository to **English-first**:
  - Primary Markdown documentation (`README.md`, `Ansible/README.md`, `docs/Sentinel-Coverage-and-Testing.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, `SUPPORT.md`, `CHANGELOG.md`) translated to English with top-of-page language switchers.
  - Added full Spanish mirror documentation (`*.es.md`) linked from every English document.
  - Translated all Terraform variable/output descriptions, validation messages, comments, Sentinel rule/workbook/automation/hunting display names, and mock test assertions to English.
  - Translated Ansible playbooks, launchers, helper scripts, unit tests, PowerShell log-generation scripts, Logic App playbook templates, Sentinel workbook JSON, and GitHub issue/PR/CI templates to English.
  - Renamed Sentinel coverage guide to `docs/Sentinel-Coverage-and-Testing.md` (`.es.md`) and Jupyter notebooks to `SOC-L2-Events.ipynb`, `SOC-L2-Hunting.ipynb`, and `SOC-L2-Log-Analysis.ipynb`.

### Added
- Standard GitHub community health and automation files:
  - GNU General Public License v3.0 ([LICENSE](LICENSE)).
  - Contributing guide ([CONTRIBUTING.md](CONTRIBUTING.md)).
  - Contributor Covenant Code of Conduct ([CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)).
  - Security policy and vulnerability reporting guide ([SECURITY.md](SECURITY.md)).
  - Support channels guide ([SUPPORT.md](SUPPORT.md)).
  - GitHub Issue templates for bug reports and feature requests under `.github/ISSUE_TEMPLATE/`.
  - Pull Request template at `.github/pull_request_template.md`.
  - Dependabot configuration at `.github/dependabot.yml`.
  - GitHub Actions CI workflow for Terraform formatting and validation at `.github/workflows/terraform-ci.yml`.

---

## [0.1.0] - 2026-10-24

### Added
- Terraform Infrastructure as Code (IaC) for the Azure SOC Level 2 Cyber Range:
  - Virtual network topology (`<prefix>-vnet`) with subnets for VMs, AKS, and Private Endpoints.
  - Lab virtual machines: Windows Server 2022 Datacenter and Ubuntu Server 22.04 LTS.
  - Microsoft Sentinel onboarded onto a central Azure Log Analytics Workspace.
  - Scheduled analytic detection rules (`LAB-Pxx`), threat hunting queries (`HUNT-01`, `HUNT-02`), workbook, automation rule, and Logic App SOAR playbooks.
  - Azure Kubernetes Service (AKS) cluster and Linux App Service for container and web telemetry.
  - Azure Key Vault with Private Endpoint, Private DNS, and RBAC for credential management.
  - Azure Monitor Data Collection Rules (DCR) and AMA extensions for Windows and Linux security telemetry, plus optional Ansible configuration for AD DS, IIS, Apache, and PostgreSQL.
- Initial documentation in [README.md](README.md) and input variable template in [terraform.tfvars.example](terraform.tfvars.example).
