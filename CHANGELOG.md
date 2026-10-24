# Registro de Cambios (Changelog)

Todos los cambios notables en este proyecto serán documentados en este archivo.

El formato se basa en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/)
y este proyecto se adhiere a [Semantic Versioning](https://semver.org/lang/es/).

---

## [Sin publicar] (Unreleased)

### Añadido
- Archivos estándar de comunidad de GitHub:
  - Licencia GNU General Public License v3.0 ([LICENSE](LICENSE)).
  - Guía de contribución ([CONTRIBUTING.md](CONTRIBUTING.md)).
  - Código de conducta para contribuyentes ([CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)).
  - Política de seguridad y reporte de vulnerabilidades ([SECURITY.md](SECURITY.md)).
  - Guía y canales de soporte ([SUPPORT.md](SUPPORT.md)).
  - Plantillas de issues de GitHub para reportes de bugs y solicitudes de funcionalidades en `.github/ISSUE_TEMPLATE/`.
  - Plantilla de Pull Request en `.github/pull_request_template.md`.
  - Configuración de Dependabot en `.github/dependabot.yml`.
  - Pipeline de integración continua de GitHub Actions para validación de Terraform en `.github/workflows/terraform-ci.yml`.

---

## [0.1.0] - 2026-10-24

### Añadido
- Infraestructura como código (IaC) en Terraform para laboratorio SOC Nivel 2:
  - Topología de red virtual (`vnet-soc-lab-prod`) con subredes para analistas, víctimas, backend y Azure Bastion.
  - Máquinas virtuales de prueba: Windows Server 2022 Datacenter y Ubuntu Server 22.04 LTS.
  - Microsoft Sentinel desplegado sobre Azure Log Analytics Workspace.
  - Conectores de datos, reglas analíticas de detección programadas (fuerza bruta RDP, ejecución de comandos anómalos).
  - Reglas de caza de amenazas (Threat Hunting) y plantillas de Playbooks de respuesta.
  - Clúster de Kubernetes (AKS) y Azure App Service para telemetría de aplicaciones y contenedores.
  - Azure Key Vault para gestión segura de credenciales y claves.
  - Azure Monitor Data Collection Rules (DCR) para Sysmon y eventos de seguridad de Windows y Linux.
- Documentación inicial en [README.md](README.md) y plantilla de variables en [terraform.tfvars.example](terraform.tfvars.example).
