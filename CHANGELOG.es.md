[English](CHANGELOG.md) | **Español**

# Registro de Cambios (Changelog)

Todos los cambios notables en este proyecto serán documentados en este archivo.

El formato se basa en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/)
y este proyecto se adhiere a [Semantic Versioning](https://semver.org/lang/es/).

---

## [Sin publicar] (Unreleased)

### Cambiado
- Estandarización completa del repositorio con **inglés como idioma principal**:
  - Documentación Markdown principal (`README.md`, `Ansible/README.md`, `docs/Sentinel-Coverage-and-Testing.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, `SUPPORT.md`, `CHANGELOG.md`) en inglés con selector de idioma en la parte superior.
  - Documentación espejo completa en español (`*.es.md`) enlazada desde cada documento en inglés.
  - Traducción al inglés de todas las descripciones de variables y outputs de Terraform, mensajes de validación, comentarios, nombres visibles (`display_name`) de reglas/workbook/automatización/hunting en Sentinel y aserciones de pruebas mock.
  - Traducción al inglés de playbooks de Ansible, lanzadores, scripts auxiliares, pruebas unitarias, script PowerShell de generación de logs, plantillas de playbooks (Logic Apps), workbook JSON de Sentinel y plantillas de GitHub (issues, PR y CI).
  - Renombrado de la guía de cobertura de Sentinel a `docs/Sentinel-Coverage-and-Testing.md` (`.es.md`) y de los notebooks Jupyter a `SOC-L2-Events.ipynb`, `SOC-L2-Hunting.ipynb` y `SOC-L2-Log-Analysis.ipynb`.

### Añadido
- Archivos estándar de comunidad y automatización de GitHub:
  - Licencia GNU General Public License v3.0 ([LICENSE](LICENSE)).
  - Guía de contribución ([CONTRIBUTING.es.md](CONTRIBUTING.es.md)).
  - Código de conducta para contribuyentes ([CODE_OF_CONDUCT.es.md](CODE_OF_CONDUCT.es.md)).
  - Política de seguridad y reporte de vulnerabilidades ([SECURITY.es.md](SECURITY.es.md)).
  - Guía y canales de soporte ([SUPPORT.es.md](SUPPORT.es.md)).
  - Plantillas de issues de GitHub para reportes de bugs y solicitudes de funcionalidades en `.github/ISSUE_TEMPLATE/`.
  - Plantilla de Pull Request en `.github/pull_request_template.md`.
  - Configuración de Dependabot en `.github/dependabot.yml`.
  - Pipeline de integración continua de GitHub Actions para validación de Terraform en `.github/workflows/terraform-ci.yml`.

---

## [0.1.0] - 2026-10-24

### Añadido
- Infraestructura como código (IaC) en Terraform para laboratorio SOC Nivel 2:
  - Topología de red virtual (`<prefijo>-vnet`) con subredes para VMs, AKS y Private Endpoints.
  - Máquinas virtuales de prueba: Windows Server 2022 Datacenter y Ubuntu Server 22.04 LTS.
  - Microsoft Sentinel desplegado sobre un workspace central de Azure Log Analytics.
  - Reglas analíticas de detección programadas (`LAB-Pxx`), consultas de caza de amenazas (`HUNT-01`, `HUNT-02`), workbook, regla de automatización y playbooks SOAR en Logic Apps.
  - Clúster de Kubernetes (AKS) y Azure App Service Linux para telemetría de contenedores y aplicaciones web.
  - Azure Key Vault con Private Endpoint, DNS privado y RBAC para gestión de credenciales.
  - Azure Monitor Data Collection Rules (DCR) y extensiones AMA para telemetría de seguridad de Windows y Linux, más configuración opcional con Ansible para AD DS, IIS, Apache y PostgreSQL.
- Documentación inicial en [README.es.md](README.es.md) y plantilla de variables en [terraform.tfvars.example](terraform.tfvars.example).
