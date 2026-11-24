[English](SUPPORT.md) | **Español**

# Soporte y Ayuda del Proyecto

¡Bienvenido al soporte del Laboratorio SOC L2 en Azure con Terraform! Aquí encontrarás las vías recomendadas para obtener asistencia y resolver dudas.

---

## Recursos de consulta previa

Antes de abrir una consulta o reporte, te sugerimos revisar los siguientes recursos:

1. **[README.es.md](README.es.md)**: Documentación integral del laboratorio, prerrequisitos, topología, despliegue paso a paso y comandos de verificación.
2. **[terraform.tfvars.example](terraform.tfvars.example)**: Plantilla de configuración con las variables requeridas y recomendadas.
3. **[docs/Sentinel-Coverage-and-Testing.es.md](docs/Sentinel-Coverage-and-Testing.es.md)** y **[Ansible/README.es.md](Ansible/README.es.md)**: Cobertura detallada, catálogo de pruebas controladas y automatización de servicios con Ansible.

---

## Canales recomendados

### 1. Preguntas y dudas conceptuales
Si tienes dudas sobre cómo funciona Microsoft Sentinel, la ingestión de telemetría con AMA/DCR, o cómo adaptar las reglas analíticas:
- Consulta o inicia un hilo en la sección **GitHub Discussions** del repositorio (pestaña *Discussions*).
- Revisa las discusiones resueltas previas.

### 2. Problemas técnicos y errores (Bugs)
Si has identificado un fallo evidente en el código Terraform o Ansible (ej. error de esquema del proveedor, fallo de dependencias entre recursos):
- Busca primero en los **GitHub Issues existentes** (tanto abiertos como cerrados) para verificar si ya fue reportado.
- Si no existe, abre un nuevo issue usando la plantilla correspondiente de [Bug Report (.github/ISSUE_TEMPLATE/bug_report.yml)](.github/ISSUE_TEMPLATE/bug_report.yml).

### 3. Solicitudes de nuevas capacidades
Si deseas proponer una nueva regla de detección, conector de datos, notebook o playbook:
- Abre una propuesta mediante la plantilla de [Feature Request (.github/ISSUE_TEMPLATE/feature_request.yml)](.github/ISSUE_TEMPLATE/feature_request.yml).

### 4. Asuntos de seguridad
- Consulta la política en [SECURITY.es.md](SECURITY.es.md) para reporte privado y confidencial.
