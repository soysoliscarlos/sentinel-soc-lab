## Descripción del cambio

Describe brevemente los cambios introducidos en este Pull Request y la motivación detrás de ellos.

Issue vinculado (si aplica): Closes #

---

## Tipo de cambio

Marca con una `x` las opciones aplicables:

- [ ] **Corrección de error (Bug fix)**: Modificación que repara un problema sin romper compatibilidad.
- [ ] **Nueva característica (New feature)**: Incorporación de nuevos recursos, reglas de Sentinel o telemetría.
- [ ] **Mejora o refactorización**: Optimización de código sin alterar la funcionalidad.
- [ ] **Actualización de documentación**: Cambios exclusivamente en guías, diagramas o comentarios.
- [ ] **Cambio crítico (Breaking change)**: Modificación que requiere rehacer el estado o variables existentes.

---

## Componentes afectados

- [ ] Microsoft Sentinel (Reglas de alerta, Hunting, Playbooks, Notebooks)
- [ ] Cómputo (Máquinas virtuales Windows/Linux)
- [ ] Redes y Seguridad (VNet, Subnets, NSG, Azure Bastion)
- [ ] Contenedores / App Services (AKS, App Service)
- [ ] Telemetría y Agentes (Sysmon, Azure Monitor Agent, DCR)
- [ ] Documentación y plantillas de configuración

---

## Lista de verificación de calidad y seguridad

Antes de enviar el PR, confirma que has completado los siguientes puntos:

- [ ] Mi código sigue las pautas descritas en [CONTRIBUTING.md](CONTRIBUTING.md).
- [ ] He ejecutado `terraform fmt -check` y el formato es conforme a las convenciones de Terraform.
- [ ] He ejecutado `terraform validate` y la sintaxis es válida.
- [ ] **Seguridad**: He verificado que **NO** he incluido credenciales reales, contraseñas, tokens de Azure ni archivos `.tfvars` con secretos en este PR.
- [ ] He actualizado la documentación relevante (como [README.md](README.md) o descripciones en [variables.tf](variables.tf)) si mis cambios lo requerían.
- [ ] Entiendo y acepto que mis contribuciones se licencian bajo la licencia **GNU GPLv3**.
