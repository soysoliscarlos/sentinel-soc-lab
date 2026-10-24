# Configuración del laboratorio con Ansible

## Alcance confirmado y estado

Implementación preparada para **ser ejecutada por Terraform**, no desplegada ni probada contra las VM. Se reutilizan las dos VM: no se añade cómputo.

`enable_ansible = true` exige `create_linux_vm = true` y `create_windows_vm = true`. Terraform rechaza la combinación si falta una VM; no se ejecuta Ansible parcialmente. Para omitir una o ambas VM, establecer `enable_ansible = false` en [las entradas Terraform](../terraform.tfvars).

Validación local realizada el 2026-10-22, incluida la ampliación de logs: formato y `terraform validate` correctos, **16 pruebas Terraform mock**, **8 pruebas Python** (incluida validación real de sintaxis rsyslog), pruebas del lanzador y de configuración de logs Windows en Windows PowerShell 5.1 y sintaxis del playbook con Ansible Core 2.20.10. No acredita instalación, conectividad ni ingesta reales.

| Destino | Configuración |
| --- | --- |
| Ubuntu 22.04 | Apache (`apache2`) y PostgreSQL de los repositorios Ubuntu; arranque automático, HTTP local y `pg_isready` verificados al ejecutar |
| Windows Server 2022 | IIS, AD DS y DNS; bosque nuevo `lab.example.test`, NetBIOS `LAB`; comprobación local HTTP, dominio, servicios y registro SRV |

IIS y DC juntos son una **excepción para este laboratorio**, no una arquitectura recomendada para producción. No se unen clientes al dominio, no se crea una base/aplicación ni usuarios PostgreSQL adicionales y no se despliegan simulaciones. PostgreSQL escucha únicamente en `localhost`; se conserva la autenticación local de los paquetes Ubuntu.

## Responsabilidades y acceso

- [Terraform](../ansible.tf) prepara red, IP privada fija `10.20.1.10` para Windows, disco Windows sin caché, secreto DSRM y OpenSSH Windows mediante la Custom Script Extension existente de auditoría. Se conserva el script de auditoría y se añade el bootstrap SSH solo al habilitar Ansible; el comando combinado se comprime para respetar el límite de `cmd.exe`. No se configura la IP estática dentro del invitado: Azure administra su asignación mediante DHCP.
- El NSG permite SSH Windows y HTTP de ambas VM **solo desde `admin_source_cidr`**; mantiene SSH Linux y RDP existentes. No abre WinRM, PostgreSQL ni puertos de AD. La VNet no pasa a usar este DC como DNS.
- La extensión Windows instala OpenSSH, selecciona PowerShell como shell, registra la clave pública Linux existente para administradores y deshabilita contraseñas SSH. Restringe la regla de firewall SSH al CIDR autorizado. Requiere salida a las fuentes de Windows Features on Demand.
- [El lanzador PowerShell](Invoke-Ansible.ps1) obtiene las claves públicas de host con Azure Run Command, autenticado contra la suscripción explícita. No usa `ssh-keyscan` ni desactiva `StrictHostKeyChecking`.
- [El lanzador Linux](run.py) crea clave e inventario temporales fuera del workspace, con directorio `0700` y clave `0600`, ejecuta [el playbook](site.yml), propaga errores y elimina los temporales al salir normalmente o por excepción. Un cierre forzoso del sistema puede impedir esa limpieza.
- Ansible configura los servicios. En Windows usa `runas` como `SYSTEM` para que las operaciones AD locales no dependan de delegación de credenciales SSH. Los módulos AD ocultan el parámetro DSRM en sus resultados.
- Después de instalar y verificar cada servicio, Ansible configura sus logs. Las DCR Linux y Windows existentes dependen de la finalización de Ansible: incorporan las nuevas fuentes solo después de preparar los archivos y canales. No se crean agentes, DCR duplicadas ni workspaces adicionales.

El NSG continúa bloqueando clientes AD, incluso dentro de la VNet. Habilitar clientes, acceso remoto a PostgreSQL, HTTPS o acceso HTTP para otro origen requiere un diseño y autorización adicionales. No se habilitan reglas genéricas `Any/Any` para facilitar el laboratorio.

## Requisitos antes de aplicar

1. Terraform se ejecuta desde **Windows PowerShell**, con Azure CLI autenticada y una distribución WSL llamada `Ubuntu`. Este lanzador no implementa ejecución desde Terraform nativo Linux ni desde un agente sin WSL.
2. En WSL: Python **3.12 o superior**, `openssh-client`, entorno `~/.venvs/soc-ansible`, dependencias y colecciones instaladas. No se instalan dependencias automáticamente durante `terraform apply`.
3. Conectividad WSL a las IP públicas de ambas VM en TCP/22. El CIDR autorizado debe corresponder a su salida pública real; revisar VPN y proxy.
4. Permisos existentes de Terraform, incluyendo cambios de NIC, NSG y extensiones; también `Microsoft.Compute/virtualMachines/runCommand/action` sobre ambas VM para obtener las claves de host. Azure CLI y el proveedor deben tener acceso a la misma suscripción. La clave SSH permite administración local y `sudo` sin contraseña en Ubuntu.
5. Revisar que `10.20.1.10` esté libre. El cambio de IP y caché de disco puede interrumpir Windows; promoción y roles pueden reiniciarlo varias veces.
6. Conservar respaldo y acceso RDP de recuperación. La cuenta `socadmin` pasa a ser una cuenta del dominio; después de la promoción usar `LAB\socadmin` para RDP. No rotar la contraseña DSRM cambiando solo el secreto: actualizar un secreto no cambia DSRM en un DC ya creado.
7. Proteger estado y plan fuera de OneDrive, preferentemente con backend remoto aprobado. La clave privada y contraseñas ya están en el estado; se añade la contraseña DSRM. Se guarda además como `windows-dsrm-password` en el Key Vault existente para recuperación. No se muestra como output ni se guarda en inventarios persistentes.
8. Permisos para actualizar `Microsoft.Insights/dataCollectionRules` y sus asociaciones al workspace existente, salida AMA hacia Azure Monitor y permisos de consulta para la verificación posterior. No se requieren puertos Syslog entrantes: ambos orígenes Linux son locales.

Se mantienen los cargos actuales de Azure. Aumentará la generación de logs y puede aumentar el consumo de disco e ingesta/retención de Log Analytics. **El usuario autorizó expresamente registrar las sentencias SQL completas.** Pueden contener contraseñas, datos personales y valores de negocio; también hay usuarios/IP y posibles tokens en las URL de acceso web. Restringir acceso al workspace y usar solo datos ficticios del laboratorio. No se aplica redacción ni se ha estimado un presupuesto adicional. La cuota actual de 1 GB/día no garantiza un límite de facturación y puede interrumpir la ingesta.

### Preparar el controlador

En una terminal **Ubuntu WSL**, desde este directorio:

```bash
sudo apt-get update
sudo apt-get install -y python3-venv openssh-client
python3 -m venv ~/.venvs/soc-ansible
~/.venvs/soc-ansible/bin/python -m pip install -r requirements.txt
~/.venvs/soc-ansible/bin/ansible-galaxy collection install -r requirements.yml
```

Si no puede usar `sudo` y `openssh-client` ya está instalado (`ssh -V`), cree el entorno sin `ensurepip`:

```bash
python3 -m venv --without-pip ~/.venvs/soc-ansible
curl -fsSL https://bootstrap.pypa.io/get-pip.py -o /tmp/get-pip.py
~/.venvs/soc-ansible/bin/python /tmp/get-pip.py && rm -f /tmp/get-pip.py
~/.venvs/soc-ansible/bin/python -m pip install -r requirements.txt
~/.venvs/soc-ansible/bin/ansible-galaxy collection install -r requirements.yml
```

Se utiliza Ansible Core 2.20 y las colecciones declaradas en [requirements.yml](requirements.yml). Las versiones tienen límites de compatibilidad, no un lock transitivo. Windows SSH tiene soporte oficial en Ansible desde 2.18 y requiere el OpenSSH incluido en Windows Server 2022 o posterior.

### Validación sin Azure

Desde `Terraform`, en PowerShell:

```powershell
terraform fmt -check -recursive
terraform validate
terraform test
.\Ansible\tests\Test-Launcher.ps1
.\Ansible\tests\Test-ServiceLogging.ps1
```

Desde este directorio, en WSL:

```bash
PYTHONDONTWRITEBYTECODE=1 ~/.venvs/soc-ansible/bin/python -m unittest discover -s tests -v
~/.venvs/soc-ansible/bin/ansible-playbook --syntax-check -i localhost, site.yml
```

El inventario mínimo produce avisos por los grupos `linux` y `windows` ausentes: no conecta ni ejecuta tareas. Las pruebas del lanzador comprueban el inventario real generado, permisos, verificación de hosts, limpieza y propagación de errores. Las pruebas PowerShell sustituyen Azure CLI, WSL, IIS y auditoría por dobles locales; comprueban transporte, idempotencia, check mode y fallos sin ejecutar comandos remotos. La prueba de configuración rsyslog usa `rsyslogd -N1` si el controlador lo tiene instalado; de lo contrario se informa como omitida. Las pruebas Terraform son planes con proveedores mock y no ejecutan provisioners; fijan explícitamente `enable_ansible=false` como base para no heredar su activación en las entradas del laboratorio. No se ha verificado aún la conectividad, promoción, reinicio ni la idempotencia sobre VM reales.

### Activar y ejecutar mediante Terraform

En el archivo de entradas protegido que se utilizará en los siguientes planes, añadir:

```hcl
enable_ansible = true
```

Desde `Terraform`, en Windows PowerShell, después de revisar presupuesto, permisos y backend:

```powershell
terraform plan -out=lab-ansible.tfplan
if ($LASTEXITCODE -ne 0) { throw "Fallo terraform plan" }
# Revisar y aprobar el plan antes de continuar.
terraform apply .\lab-ansible.tfplan
if ($LASTEXITCODE -ne 0) { throw "Fallo la configuracion del laboratorio" }
```

El `apply` ejecuta Ansible después de las VM, AMA, bootstrap Windows y secreto DSRM; luego actualiza las DCR Linux/Windows y sus asociaciones. Puede crear o modificar otros recursos pendientes del stack: revisar el plan completo, no asumir que solo contiene Ansible. Terraform puede ocultar toda la salida del provisioner porque recibe secretos sensibles; un error del lanzador provoca que falle el apply, no un resultado exitoso aparente.

La ejecución se repite cuando cambia el contenido de los archivos de automatización, destinos o credenciales incluidas en las huellas del recurso. No usa `timestamp()` ni ejecuta Ansible en cada apply sin cambios. Terraform no detecta cambios manuales dentro del SO; para reconciliar deliberadamente:

```powershell
terraform plan '-replace=terraform_data.ansible[0]' -out=lab-ansible.tfplan
# Revisar antes de aplicar el plan.
terraform apply .\lab-ansible.tfplan
```

Después de aplicar, comprobar también desde el origen autorizado HTTP en ambas IP públicas y realizar una segunda ejecución aprobada para comprobar idempotencia. No presentar las validaciones locales como evidencia de despliegue.

### Error de huella: `filesha256` devuelve un resultado inconsistente

Terraform debe leer exactamente los mismos bytes durante toda la operación y entre un plan guardado y su aplicación. Si un editor, otra ejecución de automatización o la sincronización modifica un archivo incluido en `local.ansible_files`, Terraform puede rechazar la evaluación con `function returned an inconsistent result`. El diagnóstico no identifica por sí solo cuál de esos procesos cambió el archivo.

Esperar a que terminen las ediciones y la sincronización, no reutilizar el plan anterior y generar un plan nuevo con los archivos estables:

```powershell
terraform plan -out=lab-ansible-reintento.tfplan
if ($LASTEXITCODE -ne 0) { throw "Fallo el nuevo plan" }
# Revisar el plan completo; no editar los archivos hasta terminar apply.
terraform apply .\lab-ansible-reintento.tfplan
if ($LASTEXITCODE -ne 0) { throw "Fallo el reintento" }
```

Proteger ese plan igual que el estado; ejecutar preferentemente desde una copia protegida fuera de OneDrive con el backend aprobado. Un apply fallido puede haber completado otros recursos: el nuevo plan debe reconciliar el estado actual. No borrar el estado, no usar `ignore_changes` ni sustituir la huella por `timestamp()` para eludir la comprobación.

**No desactivar `enable_ansible` como mecanismo de desinstalación.** Quita recursos auxiliares/secreto, restaura IP dinámica y caché anteriores y cierra reglas añadidas, pero **no despromueve AD ni desinstala servicios o SSH**. Democión del dominio, restauración y eliminación de datos requieren un procedimiento separado y autorizado. No reemplazar el disco ni la VM de un DC con datos que se deban conservar.

## Telemetría y referencias

La configuración siguiente se prepara con `enable_ansible=true` (ya activado en las entradas del laboratorio), pero **no se ha aplicado en este cambio**. La definición de la variable conserva `false` como valor por defecto para otras entradas. No se crean reglas de detección.

| Servicio | Generación y ruta | Tabla de Log Analytics |
| --- | --- | --- |
| IIS | W3C habilitado, archivos locales en `C:\inetpub\logs\LogFiles\W3SVC1`, rotación horaria en UTC; fuente nativa IIS de AMA | `W3CIISLog`, incluye códigos HTTP de error; no equivale a Failed Request Tracing |
| AD DS | Auditoría success/failure de usuarios, equipos, grupos de seguridad, Kerberos, validación de credenciales NTLM y Directory Service Changes; selección de IDs en la fuente Security existente | `SecurityEvent` |
| AD DS, DNS y replicación | Canales habilitados `Directory Service`, `DNS Server`, `DFS Replication`, niveles crítico/error/advertencia; se conservan System/Application | `Event` |
| Apache | `access.log` combinado y `error.log` del sitio predeterminado; rsyslog `imfile`, facility `local6`, etiquetas `apache-access` y `apache-error` | `Syslog` |
| PostgreSQL | `stderr,syslog`, facility `LOCAL5`, identificador `postgres-soc`, conexiones/desconexiones, errores y `log_statement='all'` | `Syslog` |

[La configuración Linux](linux-logging.yml) valida Apache, rsyslog y `pg_file_settings` antes de aplicar sus handlers; verifica después los valores activos PostgreSQL. Conserva `stderr` y los logs locales existentes. Apache se recarga y PostgreSQL/rsyslog se reinician si cambian sus configuraciones. [El script Windows](files/Configure-ServiceLogging.ps1) configura IIS y la auditoría después de la promoción AD, independientemente del idioma del SO; usa el valor numérico del backup de `auditpol` y elimina ese CSV temporal incluso ante error.

### Límites de cobertura

- Directory Service Changes **no crea SACL** en objetos del directorio. Los eventos 5136/5137/etc. solo se generan si los objetos ya tienen una SACL aplicable. No se afirma cobertura de todas las modificaciones LDAP ni de replicación detallada. No se habilita auditoría de acceso a todos los objetos ni debug de DNS/LDAP.
- SQL completo con `log_statement='all'` no es pgAudit ni auditoría transaccional infalible: no registra como sentencia normal consultas que fallan antes de la fase de ejecución; `log_min_error_statement=error` permite registrar las que producen errores. No garantiza reconstrucción de cada transacción.
- Syslog puede dividir sentencias largas en varios mensajes; se conservan secuencia/PID/prefijo, pero **una fila no equivale necesariamente a una consulta**. Existen límites de tamaño, throttling y posibles pérdidas del pipeline; no se garantiza entrega exactamente una vez.
- Los niveles de los archivos Apache se etiquetan en rsyslog como `info` para acceso y `error` para el archivo de errores; la severidad real original se conserva en el texto. Los offsets `imfile` pueden volver a leer algunas líneas tras una interrupción; no se ingieren además los archivos PostgreSQL por `imfile`.
- IIS soporta aquí solo el sitio predeterminado con ID 1; el script falla si no coincide con la DCR. No se instala una política de borrado de archivos IIS: vigilar disco. Apache/PostgreSQL mantienen la rotación local proporcionada por Ubuntu y el Syslog general existente.
- No se modifica la retención ni la cuota. Los eventos anteriores a la configuración efectiva pueden no enviarse. El agente debe descargar la DCR; si no hay actividad nueva, una tabla vacía no prueba un fallo. IIS puede retrasar su entrega hasta el siguiente rollover horario.
- Las rutas nuevas no están verificadas en Azure. La evidencia previa de `Heartbeat`, `Syslog` o `SecurityEvent` no demuestra que IIS/AD/Apache/PostgreSQL estén llegando ahora.

### Verificación posterior a un apply autorizado

Usar actividad normal y datos ficticios, confirmar que se generan archivos/eventos locales y consultar con el **Resource ID exacto de cada VM** en el workspace existente. No se ejecutaron estas consultas ni se generaron eventos para este cambio. Las tablas nuevas pueden no existir hasta la primera ingesta.

```kusto
W3CIISLog
| where TimeGenerated > ago(2h)
| where _ResourceId =~ "<resource-id-vm-windows>"
| summarize Registros=count(), Ultimo=max(TimeGenerated) by Computer
```

```kusto
SecurityEvent
| where TimeGenerated > ago(2h)
| where _ResourceId =~ "<resource-id-vm-windows>"
| where EventID in (4720, 4728, 4738, 4742, 4768, 4769, 4771, 4776, 5136)
| summarize Registros=count(), Ultimo=max(TimeGenerated) by Computer, EventID
```

```kusto
Event
| where TimeGenerated > ago(2h)
| where _ResourceId =~ "<resource-id-vm-windows>"
| where EventLog in ("Directory Service", "DNS Server", "DFS Replication")
| summarize Registros=count(), Ultimo=max(TimeGenerated) by Computer, EventLog
```

```kusto
Syslog
| where TimeGenerated > ago(2h)
| where _ResourceId =~ "<resource-id-vm-linux>"
| where (Facility == "local6" and ProcessName in ("apache-access", "apache-error"))
    or (Facility == "local5" and ProcessName == "postgres-soc")
| summarize Registros=count(), Ultimo=max(TimeGenerated) by Computer, Facility, ProcessName
```

Ausencia de errores AD DS puede ser normal: esos canales solo recogen advertencias y errores. Verificar la auditoría con actividad administrativa previamente aprobada; no crear/eliminar cuentas ni inducir errores como parte automática del despliegue. Consultar también [la guía de cobertura SOC](../../Research/Sentinel%20-%20Cobertura%20y%20pruebas%20del%20laboratorio.md).

- [Windows SSH en Ansible](https://docs.ansible.com/ansible/latest/os_guide/windows_ssh.html).
- [Creación de dominios con microsoft.ad.domain](https://docs.ansible.com/ansible/latest/collections/microsoft/ad/domain_module.html).
- [Configuración de OpenSSH Windows](https://learn.microsoft.com/windows-server/administration/openssh/openssh-server-configuration).
- [Recolección IIS con AMA](https://learn.microsoft.com/azure/azure-monitor/vm/data-collection-iis).
- [Recolección Syslog con AMA](https://learn.microsoft.com/azure/azure-monitor/vm/data-collection-syslog).
- [Auditoría avanzada AD DS](https://learn.microsoft.com/windows-server/identity/ad-ds/plan/security-best-practices/advanced-audit-policy-configuration).
- [Logs de PostgreSQL 14](https://www.postgresql.org/docs/14/runtime-config-logging.html).
