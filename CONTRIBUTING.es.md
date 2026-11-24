[English](CONTRIBUTING.md) | **Español**

# Guía de Contribución

¡Gracias por tu interés en contribuir a este laboratorio SOC L2 en Azure con Terraform! Este documento define las pautas y flujo de trabajo para colaborar en el proyecto de manera ordenada, segura y consistente.

---

## Código de conducta

Al participar en este proyecto, te comprometes a seguir nuestro [Código de Conducta](CODE_OF_CONDUCT.es.md). Por favor, trátalo con respeto y empatía hacia todos los miembros de la comunidad.

---

## ¿Cómo puedo contribuir?

Puedes colaborar de diferentes formas:
1. **Reportar problemas (Bugs)**: Si encuentras un fallo de sintaxis, discrepancia en los recursos o comportamiento inesperado.
2. **Proponer mejoras (Feature Requests)**: Sugerencias de nuevas reglas analíticas de Sentinel, integración de notebooks, playbooks o configuraciones de telemetría.
3. **Mejorar la documentación**: Corregir erratas, agregar diagramas explicativos, guías paso a paso o ejemplos de consultas KQL (manteniendo sincronizadas las versiones `.md` en inglés y `.es.md` en español).
4. **Enviar código o playbooks**: Proponer cambios en plantillas Terraform o automatizaciones de Ansible.

---

## Flujo de trabajo para Pull Requests (PR)

1. **Haz un Fork** del repositorio en tu cuenta de GitHub.
2. **Clona tu fork** localmente:
   ```bash
   git clone https://github.com/<tu-usuario>/<repositorio>.git
   cd Terraform
   ```
3. **Crea una rama descriptiva** para tu cambio:
   ```bash
   git checkout -b feat/new-sentinel-rule
   # o
   git checkout -b fix/rdp-nsg-rule
   ```
4. **Realiza tus cambios** siguiendo las directrices de estilo y seguridad.
5. **Valida tu código Terraform** localmente:
   ```bash
   # 1. Verificar formato
   terraform fmt -check -recursive

   # 2. Inicializar (sin backend remoto para validación)
   terraform init -backend=false

   # 3. Validar sintaxis y referencias
   terraform validate

   # 4. Ejecutar pruebas con proveedores simulados
   terraform test
   ```
6. **Haz commit de tus cambios** usando mensajes claros (se recomienda el estándar [Conventional Commits](https://www.conventionalcommits.org/) en inglés):
   ```bash
   git commit -m "feat(sentinel): add analytic rule for RDP brute-force detection"
   ```
7. **Sube tu rama y abre un Pull Request**:
   - Detalla qué problema resuelve o qué capacidad añade.
   - Vincula el Issue correspondiente si existe (`Closes #123`).
   - Completa la lista de verificación provista en la plantilla de PR.

---

## Directrices de código y estándares Terraform

### 1. Formato, nomenclatura e idioma
- Ejecuta siempre `terraform fmt -recursive` antes de enviar cambios.
- Usa `snake_case` para nombres de recursos, variables y outputs (ej. `windows_vm_size`, `enable_sentinel_analytics`).
- Escribe todos los comentarios de código, `description` de variables y outputs y mensajes de pruebas en **inglés**.
- Documenta todas las variables (`description`, `type`, y `default` cuando corresponda) en [variables.tf](variables.tf) (o en su archivo `.tf` correspondiente) y los outputs en [outputs.tf](outputs.tf).
- Al actualizar la documentación Markdown, mantén sincronizados tanto el archivo principal `.md` en inglés como su espejo `.es.md` en español.

### 2. Seguridad e Higiene de Secretos (CRÍTICO)
- **NUNCA** hagas commit de secretos, contraseñas, claves de API, claves privadas, certificados, `.tfplan` o archivos `terraform.tfstate`.
- **NUNCA** hagas commit de archivos `terraform.tfvars` con valores reales. Usa [terraform.tfvars.example](terraform.tfvars.example) para mostrar la estructura con valores de ejemplo o marcadores de posición.
- Consulta el archivo [.gitignore](.gitignore) para asegurarte de que ningún dato sensible sea rastreado por Git.
- Si detectas una fuga accidental de credenciales, repórtalo de inmediato siguiendo [SECURITY.es.md](SECURITY.es.md).

### 3. Responsabilidades de arquitectura
- Mantén la infraestructura en la nube, identidades, diagnósticos, DCR y recursos de Sentinel en Terraform.
- Las configuraciones post-despliegue de servicios dentro de los sistemas operativos (ej. IIS/Apache, AD DS, PostgreSQL) deben gestionarse con Ansible en [Ansible/](Ansible/README.es.md).

---

## Licencia de las contribuciones

Al contribuir al repositorio, aceptas que todo código y documentación entregada será distribuida bajo los términos de la licencia **GNU General Public License v3.0 (GPLv3)**. Consulta [LICENSE](LICENSE) para más detalles.
