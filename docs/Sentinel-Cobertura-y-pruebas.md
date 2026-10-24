# Microsoft Sentinel: cobertura y pruebas del laboratorio SOC L2

Fecha: 2026-10-22.

**Actualización de configuración (2026-10-22):** se preparó [Ansible invocado por Terraform](../Ansible/README.md), sin ejecutarlo: IIS y bosque AD `lab.example.test` sobre Windows; Apache y PostgreSQL sobre Ubuntu. `enable_ansible` está activado en las entradas del laboratorio, no en el valor por defecto. Después de instalar y verificar los servicios se configuran sus logs y se amplían las DCR existentes: IIS en `W3CIISLog`; cuentas/Kerberos/NTLM de AD en `SecurityEvent`; Directory Service/DNS/DFS con errores y advertencias en `Event`; Apache `local6` y PostgreSQL `local5` en `Syslog`. Se autorizó explícitamente `log_statement='all'`: puede exponer secretos y aumentar costos. No se aplicó esta ampliación ni se verificó su ingesta; las consultas y límites están en la guía enlazada.

**Estado:** procedimientos propuestos, no ejecutados. En una revisión posterior de solo lectura se consultó Azure y se comprobó ingesta de los recursos principales. La evidencia real y sus límites están en [Verificación real de conexiones e ingesta](../README.md#verificación-real-de-conexiones-e-ingesta); los ejemplos de incidentes de esta guía siguen siendo ilustrativos. No se aplicaron cambios ni se ejecutaron estas pruebas.

**Cambio de alcance:** Application Gateway/WAF fue retirado del código por decisión del usuario. P05 usa ahora acceso directo HTTPS a App Service; P06 queda como escenario histórico deshabilitado, no como prueba de la cobertura actual. No se debe recrear WAF para ejecutar esta guía sin nueva aprobación.

## 1. Qué significa monitorear todos los recursos

Sentinel no descubre ni recoge automáticamente toda la actividad por estar habilitado. Debemos conectar cuatro capas:

1. **Plano de control:** creación y cambios de recursos, reglas de red, diagnósticos y RBAC mediante `AzureActivity`.
2. **Plano de datos y sistema operativo:** accesos a secretos, solicitudes HTTP, procesos, autenticación y operaciones Kubernetes mediante diagnósticos y AMA/DCR.
3. **Detección:** reglas analíticas que transformen eventos en alertas e incidentes; los logs por sí solos no crean incidentes.
4. **Cobertura:** inventario de fuentes esperadas, última recepción, volumen y salud de conectores/reglas.

Una IP pública, NIC, disco o Private Endpoint no necesariamente ofrece un log de seguridad por cada acceso. Su cobertura se compone de Activity Log, métricas, estado y señales de los servicios que los utilizan. Sentinel es el SIEM; disponibilidad, latencia y métricas deben complementarse con Azure Monitor.

Fuentes locales revisadas: [alcance del despliegue](../README.md), [recolección](../monitoring.tf), [VM y AMA](../compute.tf), [Key Vault](../key_vault.tf) e [investigación original de Sentinel](./Configurar%20Sentinel%20Terraform%20y%20Notebooks.md).

## 2. Cobertura definida y configuraciones que podemos agregar

“Definido” significa presente en Terraform; consultar la evidencia enlazada para distinguir lo ya desplegado de las correcciones aún pendientes de aplicar.

| Recurso o capa | Definido actualmente | Tabla esperada | Mejora propuesta y límite |
| --- | --- | --- | --- |
| Suscripción y grupo del lab | Diagnóstico de ocho categorías de Activity Log | `AzureActivity` | Detectar cambios de NSG, RBAC y diagnósticos. Filtrar por grupo o ID: el origen incluye otros recursos de la suscripción. Los cambios del propio grupo y los de ámbito suscripción necesitan filtros específicos. |
| VM Ubuntu | AMA, identidad, rsyslog y DCR con auth/authpriv/daemon/syslog/kern | `Syslog`, `Heartbeat` | Detección de fallos SSH y uso de sudo. Agregar auditd y una ruta de ingesta validada si se necesitan procesos/archivos: Syslog no equivale a auditoría completa. SSH usa claves; no habilitar contraseñas para probar. |
| VM Windows | AMA y DCR con eventos Security seleccionados y errores/advertencias de System/Application; extensión de auditoría logon/procesos preparada | `SecurityEvent`, `Event`, `Heartbeat` | Ingesta comprobada. La extensión aún no aplicada habilita argumentos 4688; los 221 eventos 4688 revisados no los tenían. Auditoría adicional de cuentas sigue fuera de esa extensión. |
| IIS, AD DS y DNS en Windows | Preparados en Ansible y DCR, sin aplicar: IIS W3C horario, cuentas/grupos/equipos, Kerberos/NTLM, Directory Service Changes y canales de servicio | `W3CIISLog`, `SecurityEvent`, `Event` | No confundir con App Service. No se crean SACL: eventos de cambios de objetos AD requieren SACL aplicable. No se habilita debug LDAP/DNS ni Failed Request Tracing. Ingesta pendiente de comprobar. |
| Apache y PostgreSQL en Ubuntu | Preparados en Ansible y DCR, sin aplicar: rsyslog `imfile` para acceso/errores Apache `local6`; PostgreSQL nativo Syslog `local5`, conexiones/desconexiones, errores y SQL completo | `Syslog` | Filtrar `ProcessName` (`apache-access`, `apache-error`, `postgres-soc`) y `_ResourceId`. No es pgAudit. SQL largo puede fragmentarse; no se garantiza entrega exactamente una vez ni registro transaccional completo. |
| PowerShell y Sysmon | No implementados | Según ruta: `Event`, `WindowsEvent` o tabla personalizada | Script Block Logging 4104 requiere habilitación y colección de su canal Operational, hoy fuera de la DCR. Sysmon requiere instalación, configuración e ingesta propia. No asumir que aparecen en `SecurityEvent`. |
| App Service Linux B1 | Diagnósticos HTTP, consola, publicación, restricciones IP y plataforma | `AppServiceHTTPLogs`, `AppServiceConsoleLogs`, `AppServiceAuditLogs`, `AppServiceIPSecAuditLogs`, `AppServicePlatformLogs` | Desplegar una aplicación de prueba aprobada para generar actividad útil; no hay aplicación definida. Agregar telemetría de aplicación/Application Insights si el objetivo es trazar errores o dependencias. |
| Application Gateway/WAF | Retirado del código; no existe Gateway en el inventario consultado | No se exige telemetría WAF | Se observó una política WAF residual sin Gateway. No equivale a protección activa; no se modifica ni se vuelve a desplegar. |
| AKS | Container Insights con tres streams y diagnósticos de auditoría administrativa/control plane; `guard` añadido, sin aplicar | `ContainerLogV2`, `KubeEvents`, `KubePodInventory`, `AKSAuditAdmin`, `AKSControlPlane` | Ingesta comprobada salvo `ContainerLogV2`, sin eventos y con solo pods `kube-system` observados. `kube-audit-admin` excluye `get` y `list`; ampliar a `kube-audit` requiere estimación y aprobación. |
| Key Vault | `AuditEvent`, destino dedicado, acceso privado y público restringido | `AZKVAuditLogs` | Alertar por denegaciones y lecturas de secretos fuera del patrón esperado. Private Endpoint no elimina la necesidad de RBAC ni de auditoría. |
| VNet, NSG, NIC, IP, rutas y Private Endpoint | Cambios ARM visibles mediante Activity Log; sin flujo de tráfico configurado | `AzureActivity`; flujos aún sin destino definido | Agregar VNet flow logs, almacenamiento y, si se aprueba, Traffic Analytics. Los flujos crudos van a Storage: no aparecen automáticamente en Sentinel. Validar cobertura por servicio y ruta de ingesta. |
| Discos, plan App Service, balanceador y recursos administrados de AKS | Visibilidad de cambios ARM donde estén en el alcance del diagnóstico | `AzureActivity`; métricas en Azure Monitor | Inventariar también el grupo administrado de AKS. Habilitar alertas de salud/métricas donde corresponda; no instalar AMA manualmente en VMSS administrados por AKS. |
| Identidad Entra ID | Sin conector definido | `SigninLogs`, `AuditLogs` y otras tablas según selección | Agregar conector Entra ID si se desea observar autenticación del tenant. Confirmar licencias, roles y alcance: no es una fuente limitada al grupo del lab. |
| Defender | Defender for Servers (P1/P2) y MDE opcionales vía `enable_defender_for_servers`; sin otros planes ni conectores | `SecurityAlert`, `SecurityIncident`; eventos avanzados según conector | Evaluar Defender for Servers, Containers, App Service y Key Vault según objetivo/costo. AMA no equivale a Defender for Endpoint. Elegir integración XDR/Defender for Cloud y evitar duplicar alertas/incidentes. |
| Sentinel | Onboarding sobre un workspace compartido | Tablas de las fuentes anteriores | Agregar contenido, reglas, workbooks y salud/auditoría. `SentinelHealth` cubre recursos compatibles; `SentinelAudit` audita reglas analíticas, no toda la actividad de Azure. |

**Red:** para una configuración nueva usar VNet flow logs. No proponer nuevos NSG flow logs: no se pueden crear desde el 30-06-2025 y su retirada está prevista para el 30-09-2027. Validar las limitaciones de VNet flow logs; no garantizan visibilidad de cada endpoint PaaS ni equivalen a captura de paquetes.

## 3. Orden recomendado de configuración

### Fase A: comprobar lo que ya existe en código

1. Confirmar el workspace de destino y listar recursos realmente desplegados, incluidos los del grupo administrado de AKS. No deducirlo solo de Terraform.
2. Revisar AMA, identidades, asociaciones DCR y salida hacia Azure Monitor en ambas VM.
3. Comprobar diagnósticos de cada servicio, categorías admitidas y destino dedicado. Una tabla puede no existir hasta que llegue el primer evento.
4. Activar las políticas de auditoría Windows necesarias, con cuidado de no registrar secretos en líneas de comandos.
5. Generar eventos benignos de las pruebas de esta guía y comprobar su llegada.

No crear una segunda DCR desde el conector Windows Security Events vía AMA sin revisar la administrada por Terraform: la superposición puede duplicar eventos y gasto. Instalar una solución de Content Hub no sustituye la configuración de sus conectores.

### Fase B: convertir telemetría en detecciones

- Instalar desde **Content Hub** las soluciones aplicables a Windows Security Events, Syslog y Azure Activity; revisar sus dependencias y adaptar plantillas al esquema dedicado. WAF no aplica al alcance actual.
- Crear reglas programadas del apartado 7 con mapeo de entidades y creación de incidentes. Comenzar con reglas etiquetadas `LAB` y severidad baja/media.
- Habilitar **Auditing and health monitoring** en Settings de Sentinel: tablas `SentinelHealth` y `SentinelAudit`, creadas tras los primeros eventos compatibles.
- Crear un workbook de cobertura/volumen y una watchlist de fuentes esperadas. Una fuente silenciosa y una fuente desconectada no se distinguen solo contando eventos.
- Evaluar UEBA después de conectar fuentes de identidad compatibles. No genera visibilidad donde no hay datos ni sustituye reglas deterministas de prueba.
- Inicialmente, usar automatización solo para etiquetar/asignar incidentes. No habilitar bloqueo de IP, aislamiento de VM o revocación de identidades sin aprobación separada.

### Fase C: ampliar visibilidad con presupuesto aprobado

Agregar Entra ID, Defender, auditoría completa de AKS, flujos de red y telemetría de aplicación según las preguntas de investigación. No activar todas las fuentes de alto volumen indiscriminadamente.

### Permisos, costos y responsabilidades

| Acción | Condición previa |
| --- | --- |
| Consultar y analizar | Acceso de lectura a logs y permisos de Sentinel adecuados; por ejemplo Log Analytics Reader y Microsoft Sentinel Reader en el alcance necesario. |
| Gestionar reglas e incidentes | Microsoft Sentinel Contributor para reglas; Microsoft Sentinel Responder para operación de incidentes. No basta con poder leer el workspace. |
| Configurar diagnósticos y DCR | Permisos de Azure Monitor y sobre los recursos afectados. El diagnóstico de Activity Log requiere alcance de suscripción. |
| Configurar roles o conectores de tenant | Permisos específicos de RBAC/Entra indicados por cada conector. No otorgar Global Administrator por comodidad. |
| Habilitar Defender y flujos | Aprobar costos de planes, Storage, análisis y volumen. Las licencias y planes de Defender/Entra son independientes del onboarding de Sentinel. |
| Implementación posterior | Terraform: recursos, diagnósticos, DCR y reglas compatibles con el proveedor. Ansible u otra configuración de SO: auditoría Windows, auditd, IIS/Apache y Sysmon. Esta guía no implementa ninguno. |

El workspace define 30 días de retención y umbral de 1 GB/día por defecto. Confirmar valores efectivos antes de probar. El umbral diario **no es un límite estricto de gasto**: puede haber exceso, fuentes exentas y pérdida de cobertura si se detiene ingesta. Crear presupuesto y alertas de costo/volumen. Mantener las tablas usadas por estas reglas en plan **Analytics**; no trasladarlas a Basic/Auxiliary suponiendo equivalencia para reglas programadas.

## 4. Cómo observar los resultados en Sentinel

En el portal de Defender, seleccionar el workspace de Sentinel y usar las experiencias de búsqueda/consulta, Analytics e Incidents disponibles para ese workspace. En Azure, si sigue disponible la experiencia del tenant, usar Sentinel > Logs, Analytics e Incidents.

1. **Evento:** ejecutar la consulta KQL correspondiente sobre las tablas del workspace.
2. **Alerta:** comprobar que la regla habilitada se ejecutó después de la ingesta y superó su umbral.
3. **Incidente:** comprobar que la regla tiene creación de incidentes habilitada; abrir entidades, línea temporal y eventos.

Los nombres de menús pueden variar. Las consultas siguientes usan el esquema de **Log Analytics/Sentinel**, no las tablas nativas `AlertInfo`/`AlertEvidence` de Advanced Hunting. Elegir el contexto del workspace; no sustituir nombres de tablas a ciegas.

**Antes de consultar:** revisar el esquema disponible. Si aparece “Failed to resolve table”, falta la tabla o el contexto es incorrecto; no significa “sin ataques”. No se usan uniones tolerantes a fallos para ocultar fuentes ausentes. Campos/tablas deben verificarse en el entorno; estas consultas se contrastaron con documentación, no se ejecutaron contra Azure.

## 5. Preparación y límites de las pruebas

- Solo recursos propios del lab, con autorización y una ventana acordada. No se ejecuta ninguna prueba al crear este documento.
- Registrar hora UTC inicial/final, recurso, usuario de prueba e IP de origen. Usar marcadores `SOC-L2-Pxx`, sin datos personales ni secretos.
- Ejecutar primero las consultas de ingesta. Presupuestar inicialmente una espera de 5–15 minutos y volver a consultar hasta 30 minutos si hace falta; no es un SLA ni una garantía. Medir retraso real con `ingestion_time()` cuando esté disponible.
- Para pruebas de autenticación usar cuentas desechables sin privilegios. Revisar política de bloqueo; si el umbral de bloqueo es bajo, reducir intentos y umbral de la regla. Nunca probar contraseñas de cuentas reales.
- No desactivar NSG, Defender, MFA o auditoría; no abrir puertos al mundo. No usar malware, fuerza bruta, explotación, borrado de logs o recursos productivos.
- Usar HTTPS directo a App Service en el alcance actual. El escenario histórico de P06 solo contemplaba HTTP restringido: nunca enviar credenciales/cookies/secretos por esa ruta.
- Los comandos de VM Windows se ejecutan dentro de esa VM; `logger` se ejecuta dentro de Ubuntu; comandos `az`, `kubectl` y `curl.exe` desde el equipo administrador autorizado. Sustituir todos los marcadores `<...>` antes de ejecutar.

### Automatización con PowerShell

[Invoke-SocLabLogGeneration.ps1](../scripts/Invoke-SocLabLogGeneration.ps1) ejecuta las pruebas desde el equipo administrador con Azure CLI. Las VM se operan con `az vm run-command` y AKS con `az aks command invoke`, sin SSH, RDP, `kubectl` ni `kubelogin` locales. Cada ejecución usa marcadores `SOC-L2-Pxx-<RunId>`, limpia el namespace y la etiqueta temporales y guarda las consultas KQL en `%TEMP%\soc-l2-loggen\<RunId>-consultas.kql`.

| Grupo (`-Test`) | Pruebas | Tabla en Sentinel |
|---|---|---|
| `Windows` | P02 (varios 4625 con usuarios inexistentes), P03 (varios 4688 con marcador), P14 (evento Warning en Application), P15 (ciclo de vida de cuentas/grupos de dominio desechables: 4720/4722/4724/4725/4726/4727/4728/4729/4730/4732/4733/4738 y 4776) | `SecurityEvent`, `Event` |
| `Linux` | P04 (`logger` en authpriv/auth/daemon y marcador sudo), P04B (SSH y `su` fallidos con usuarios inexistentes `socp04<short>`), P13 (login PostgreSQL fallido) | `Syslog` (auth/authpriv/daemon, `sshd`/`su`, `local5`) |
| `WebServers` | P11 (Apache), P12 (IIS) | `Syslog` (`local6`), `W3CIISLog` |
| `AppService` | P05 | `AppServiceHTTPLogs` |
| `KeyVault` | P07 (lista metadatos; 200 sobre `linux-ssh-public-key` si existe y 404 sobre un secreto inexistente; sin VM Linux omite la lectura exitosa, nunca lee contraseñas) | `AZKVAuditLogs` |
| `Arm` | P09 (etiqueta `SOCPrueba` en la VM Linux, agregada y retirada) | `AzureActivity` |
| `Aks` | P08 (namespace `soc-l2-p08-<RunId>` y ConfigMap), P10 (pod no privilegiado que escribe a stdout), P10E (pod con etiqueta de imagen inexistente: `ErrImagePull`) | `AKSAuditAdmin`, `ContainerLogV2`, `KubeEvents` (por defecto solo eventos `Warning`) |

```powershell
.\Terraform\scripts\Invoke-SocLabLogGeneration.ps1 -WhatIf                 # solo descubre recursos
.\Terraform\scripts\Invoke-SocLabLogGeneration.ps1 -Test Windows, Linux -Verify
.\Terraform\scripts\Invoke-SocLabLogGeneration.ps1 -VerifyOnly -RunId <RunId>
```

Los argumentos quedan en texto claro en 4688/Syslog; las contraseñas que usan P02, P13 y P15 son ficticias. P13, P11 y P12 requieren `enable_ansible`. P15 requiere que la VM Windows sea controlador de dominio (módulo `ActiveDirectory`) y crea cuentas/grupos desechables que elimina en un bloque `finally`. Con `-Verify`, el script consulta el workspace mediante la API de Log Analytics hasta que aparece cada marcador.

Terraform lo ejecuta como último paso del apply cuando `enable_log_generation = true` (ver [Terraform/log_generation.tf](../log_generation.tf)). Antes de generar actividad, el script espera a que ambas VM envíen `Heartbeat` y AKS envíe `KubePodInventory`, y concede un margen a los diagnostic settings (`-WaitForSourcesMinutes`, `-InitialDelaySeconds`).

## 6. Pruebas controladas y visualización esperada

### P01. Validar vida de los agentes de ambas VM

**Acción:** mantener ambas VM encendidas y AMA operativo, sin detener servicios. Comparar los nombres de equipo reales: Windows está configurado como `soc-win`, aunque el recurso Azure se llama `soc-l2-windows`.

```kql
let Esperados = datatable(Equipo:string)
[
    "soc-l2-linux",
    "soc-win"
];
Esperados
| join kind=leftouter (
    Heartbeat
    | where TimeGenerated > ago(24h)
    | extend Equipo = tolower(tostring(split(Computer, ".")[0]))
    | summarize UltimoHeartbeat = max(TimeGenerated) by Equipo
) on Equipo
| extend Estado = case(
    isnull(UltimoHeartbeat), "Sin heartbeat en 24h",
    UltimoHeartbeat < ago(10m), "Retrasado",
    "Reciente")
| project Equipo, UltimoHeartbeat, Estado
```

**Esperado:** dos filas, ambas `Reciente`. Un equipo sin eventos también aparece por el inventario izquierdo. Adaptar nombres si se cambia el prefijo. Para una regla de cobertura agregar `| where Estado != "Reciente"`; excluir mantenimientos aprobados.

**Cómo se vería:** workbook con dos equipos en verde. Esto prueba AMA, no la llegada de `SecurityEvent` o `Syslog`; validar también P02/P04. No hay incidente salvo que se configure la regla de ausencia.

### P02. Fallos de autenticación Windows

**Requisitos:** auditoría de Logon/Failure habilitada, cuenta local desechable y recepción de 4625. Evitar una cuenta con permisos de administración.

**Acción:** realizar manualmente hasta tres inicios de sesión fallidos de esa cuenta, en menos de cinco minutos y desde el acceso autorizado. Si se bloquea en tres o menos intentos, reducir la prueba y ajustar el umbral. No automatizar intentos.

```kql
SecurityEvent
| where TimeGenerated > ago(5m)
| where EventID == 4625
| where Computer startswith "soc-win"
| summarize Intentos = count(), Inicio = min(TimeGenerated),
    Fin = max(TimeGenerated) by Computer, Account, IpAddress
| where Intentos >= 3
```

**Esperado:** fila con equipo, cuenta, IP cuando exista y tres o más eventos. Si NLA, firewall o la ruta de acceso impiden llegar al SO, puede no haber 4625; no confundir rechazo de red con fallo de logon.

**Cómo se vería:** alerta `LAB-P02 - Fallos de autenticación Windows`, severidad media, entidades Host/Account/IP e incidente asociado si se habilita. Tres fallos son un umbral didáctico, no prueba de fuerza bruta.

### P03. Auditoría de creación de procesos sin ejecutar acciones dañinas

**Requisitos:** Audit Process Creation y política Include command line in process creation events habilitadas. La DCR ya selecciona 4688, pero no habilita esas políticas. Se preparó [una extensión de configuración](../compute.tf) que ejecuta [Configure-WindowsAudit.ps1](../scripts/Configure-WindowsAudit.ps1), aún sin aplicar; no ejecutar esta prueba esperando coincidencias hasta validar la política.

**Acción en PowerShell dentro de Windows:**

```powershell
cmd.exe /c "echo SOC-L2-P03"
```

```kql
SecurityEvent
| where TimeGenerated > ago(30m)
| where EventID == 4688
| where Computer startswith "soc-win"
| where CommandLine contains "SOC-L2-P03"
| project TimeGenerated, Computer, Account, NewProcessName, CommandLine
| order by TimeGenerated desc
```

**Esperado:** al menos un evento de `cmd.exe` con el marcador. Si existe 4688 pero `CommandLine` está vacío, revisar la política. No usar credenciales en argumentos.

**Cómo se vería:** alerta informativa/baja `LAB-P03 - Marcador de proceso`, con Host y Account. No implica una detección nativa de malware ni de PowerShell 4104. No requiere limpieza.

### P04. Recorrido completo de Linux Syslog

**Acción dentro de Ubuntu:**

```bash
logger -p authpriv.notice -t soc-lab "SOC-L2-P04 prueba benigna de ingesta"
```

```kql
Syslog
| where TimeGenerated > ago(30m)
| where SyslogMessage contains "SOC-L2-P04"
| project TimeGenerated, Computer, Facility, SeverityLevel,
    ProcessName, SyslogMessage
| order by TimeGenerated desc
```

**Esperado:** al menos un registro con facility `authpriv`, proceso/tag relacionado con `soc-lab` y marcador. Comprueba generación local, rsyslog, AMA, DCR y workspace; no simula un acceso SSH real.

**Cómo se vería:** fila de Logs y, con regla explícita, incidente de severidad baja `LAB-P04 - Validación Syslog`. Para futura detección de SSH, validar primero los mensajes reales de `sshd` de este SO antes de escribir un parser.

### P05. Solicitud HTTP de prueba hacia el backend

**Requisitos:** App Service accesible directamente por HTTPS. No hay aplicación en el código base; si no sirve una página saludable, preparar primero una aplicación de prueba aprobada.

```powershell
curl.exe --max-time 15 -i "https://<NOMBRE_APP>.azurewebsites.net/SOC-L2-P05-no-existe"
```

**Consulta de llegada al App Service:**

```kql
AppServiceHTTPLogs
| where TimeGenerated > ago(30m)
| where CsUriStem contains "SOC-L2-P05"
| project TimeGenerated, CsHost, CsMethod, CsUriStem, ScStatus, CIp
```

**Esperado:** registro en `AppServiceHTTPLogs`. Un 404 es esperable solo si la aplicación devuelve 404 para rutas inexistentes; una SPA podría devolver 200. Un 5xx indica investigar disponibilidad o aplicación, no demuestra un ataque. No se exige un estado HTTP fijo.

**Cómo se vería:** solicitudes en Logs y gráfico por código HTTP. Revisar la IP observada según la ruta real. Sin regla adicional no crea incidente.

### P06. Bloqueo WAF determinista con un marcador inocuo

**No aplica al despliegue actual.** Se conserva como referencia histórica. No ejecutar sus pasos ni crear recursos/reglas WAF sin aprobar un nuevo alcance.

**Configuración adicional propuesta, aún no implementada:** agregar mediante el flujo de cambios una regla personalizada temporal a la política del lab, con prioridad libre anterior a las demás reglas personalizadas, condición exacta del encabezado `X-SOC-Lab-Test` igual a `SOC-L2-P06` y acción `Block`. Confirmar política asociada y modo Prevention. No cambiar a Allow ni desactivar reglas administradas.

Esto valida la ruta de bloqueo y logging del WAF sin enviar payloads de explotación. **No prueba cobertura OWASP/SQLi/XSS.**

```powershell
curl.exe --max-time 15 -i -H "X-SOC-Lab-Test: SOC-L2-P06" "http://<IP_PUBLICA_GATEWAY>/SOC-L2-P06"
```

```kql
AGWFirewallLogs
| where TimeGenerated > ago(30m)
| where Action =~ "Blocked"
| where RequestUri contains "SOC-L2-P06"
| project TimeGenerated, ClientIp, RequestUri, Action,
    RuleId, Message, TransactionId
```

**Esperado:** respuesta 403 y evento `Blocked` de la regla personalizada. Investigar `RuleId`/mensaje y correlacionar `TransactionId` con `AGWAccessLogs`. Si el NSG bloquea antes del Gateway, no habrá evento WAF. No debe llegar al backend.

**Cómo se vería:** incidente `LAB-P06 - Solicitud bloqueada por WAF`, severidad baja para esta prueba, entidad IP y detalles de la regla. No reportar el incidente como ataque confirmado.

**Limpieza:** eliminar únicamente la regla temporal mediante el mismo flujo que la creó; verificar que una solicitud benigna sin encabezado vuelve a seguir la ruta habitual. No crear drift manual si Terraform administra la política.

### P07. Acceso auditado a un secreto no sensible de Key Vault

**Requisitos:** usar exclusivamente el secreto existente `linux-ssh-public-key`, que contiene una clave pública. Identidad autorizada por red y RBAC. No usar `windows-admin-password`.

```powershell
az keyvault secret show --vault-name <NOMBRE_VAULT> --name linux-ssh-public-key --query id -o tsv
```

Aunque la salida solo muestra el ID, la API hace una lectura real del secreto. No usar esta técnica para extraer material privado.

```kql
AZKVAuditLogs
| where TimeGenerated > ago(30m)
| where OperationName =~ "SecretGet"
| where RequestUri contains "linux-ssh-public-key"
| project TimeGenerated, OperationName, HttpStatusCode,
    ResultType, CallerIpAddress, Identity, RequestUri
```

**Esperado:** operación `SecretGet` con 200 para acceso autorizado. La consulta puede mostrar intentos repetidos del cliente; no exigir exactamente una fila. Para una variante de denegación usar una identidad de prueba previamente aprobada sin permiso de lectura, sin modificar roles del administrador.

**Cómo se vería:** lectura auditada en Logs. Una regla separada con `HttpStatusCode == 403` genera `LAB-P07 - Acceso denegado a Key Vault` solo si se realiza esa variante. Un 403 requiere revisar red/RBAC; no demuestra compromiso.

### P08. Cambio administrativo inocuo en Kubernetes

**Requisitos:** contexto `kubectl` del clúster del lab, acceso autorizado y nombre de namespace libre. Verificar el contexto antes de crear objetos; si `soc-l2-p08` ya existe, detenerse y acordar otro nombre.

```powershell
kubectl config current-context
kubectl create namespace soc-l2-p08
kubectl create configmap soc-l2-p08 --namespace soc-l2-p08 --from-literal=mensaje=SOC-L2-P08
```

```kql
AKSAuditAdmin
| where TimeGenerated > ago(30m)
| where Verb in ("create", "delete")
| where tostring(ObjectRef.namespace) == "soc-l2-p08"
| where tostring(ObjectRef.resource) == "configmaps"
| extend Usuario = tostring(User.username),
    Codigo = toint(ResponseStatus.code),
    Objeto = tostring(ObjectRef.name)
| project TimeGenerated, Verb, Usuario, Objeto, Codigo,
    SourceIps, AuditId, Stage
```

**Esperado:** creación del ConfigMap con código 201 en el evento de respuesta; pueden aparecer varias etapas con el mismo `AuditId`, algunas sin código. No usar `kubectl get` como única prueba de `AKSAuditAdmin`: excluye get/list.

**Cómo se vería:** alerta baja `LAB-P08 - Cambio Kubernetes`, con usuario, objeto y clúster como detalles. No se necesita desplegar un contenedor privilegiado ni modificar ClusterRoleBindings.

**Limpieza, solo de los objetos creados para esta prueba:**

```powershell
kubectl delete configmap soc-l2-p08 --namespace soc-l2-p08
kubectl delete namespace soc-l2-p08
```

La eliminación también genera auditoría. No eliminar un namespace preexistente o con objetos ajenos a esta prueba.

### P09. Cambio ARM reversible sin debilitar seguridad

**Acción:** mediante un cambio aprobado agregar la etiqueta temporal `SOCPrueba=SOC-L2-P09` solo a una VM del lab y restaurar después el valor previo. Si se gestiona con Terraform, usar ese flujo; no ejecutar un apply únicamente para esta guía. Nunca reemplazar todas las etiquetas ni tocar NSG/RBAC para generar señal.

```kql
AzureActivity
| where TimeGenerated > ago(30m)
| where ResourceGroup =~ "soc-l2-rg"
| where OperationNameValue in~ (
    "MICROSOFT.COMPUTE/VIRTUALMACHINES/WRITE",
    "MICROSOFT.RESOURCES/TAGS/WRITE")
| project TimeGenerated, OperationNameValue, ActivityStatusValue,
    Caller, CallerIpAddress, ResourceId, CorrelationId
| order by TimeGenerated desc
```

**Esperado:** operación de escritura sobre el recurso de prueba; la operación exacta depende del cliente/API. Correlacionar por ID, usuario y ventana temporal. Activity Log no garantiza mostrar el contenido exacto de la etiqueta; el marcador se valida también en el recurso.

**Cómo se vería:** alerta baja `LAB-P09 - Cambio administrativo en VM`, con cuenta/IP cuando estén disponibles. Diferenciar Started/Accepted/Succeeded para no contar fases como cambios independientes. Eliminar/restaurar solo la etiqueta de prueba al terminar.

## 7. Configuración de reglas para que aparezcan incidentes

Crear inicialmente reglas programadas con prefijo `LAB`, ventana de consulta de 15 minutos y ejecución cada 5 minutos, salvo P02 que usa una ventana de 5 minutos. La consulta incorporada a cada regla debe usar la misma ventana que su configuración, no copiar sin cambios los 30 minutos de investigación anteriores.

| Regla propuesta | Lógica mínima | Severidad de lab | Entidades/detalles |
| --- | --- | --- | --- |
| LAB-P01 - Fuente sin heartbeat | Consulta P01 más filtro de estado distinto de Reciente; intervalo 5 min, mirar 24 h | Media | Host; excluir mantenimientos y apagados acordados |
| LAB-P02 - Fallos Windows | P02: al menos 3 eventos por equipo/cuenta/IP en 5 min, o umbral seguro acordado | Media | Host, Account, IP si válida |
| LAB-P03 - Marcador de proceso | P03 con ventana 15 min; una coincidencia | Baja | Host, Account; CommandLine como detalle |
| LAB-P04 - Validación Syslog | P04 con ventana 15 min; una coincidencia | Baja | Host; facility y mensaje |
| LAB-P06 - Bloqueo WAF | Deshabilitada/no crear: WAF fuera del alcance actual | Baja | Solo referencia histórica |
| LAB-P07 - KV denegado | P07 con ventana 15 min y filtro adicional `HttpStatusCode == 403` | Baja | IP; Identity como detalle hasta validar su estructura |
| LAB-P08 - Cambio Kubernetes | P08 con ventana 15 min, `Stage == "ResponseComplete"` y `Codigo == 201` para creación | Baja | Usuario y recurso como detalles; no mapear a Account sin validar su formato |
| LAB-P09 - Cambio administrativo | P09 con ventana 15 min y `ActivityStatusValue =~ "Succeeded"` | Baja | Account/IP si disponibles; ResourceId y CorrelationId |

En todas:

- Configurar umbral **número de resultados > 0**. En P02 cada fila ya cumple el conteo de tres eventos: no configurar también “tres resultados”.
- Habilitar creación de incidentes y decidir agrupación de alertas del mismo recurso/marcador durante 1 hora. La agrupación evita múltiples incidentes, no necesariamente alertas repetidas.
- Ventanas de 15 minutos ejecutadas cada 5 minutos se solapan: un mismo evento puede disparar varias veces. Ajustar agrupación/deduplicación después de observar el retraso real; no prometer exactamente una alerta.
- Mapear Account con identificadores correctos (nombre/dominio u object ID si procede), Host con nombre/dominio e IP solo si es una dirección válida. No tratar un JSON `Identity` completo como identificador de cuenta.
- Guardar marcador, recurso, regla y correlación como detalles personalizados. No mapear estos ejercicios benignos a una técnica MITRE como si demostraran un ataque.
- Usar la prueba de consultas y simulación de resultados del asistente de Analytics cuando esté disponible antes de habilitar la regla.

**Ejemplo ilustrativo en Incidents:**

| Título | Severidad | Estado inicial configurado | Evidencia |
| --- | --- | --- | --- |
| LAB-P02 - Fallos de autenticación Windows | Media | New | `soc-win`, cuenta de prueba, 3 eventos 4625 en 5 min |
| LAB-P06 - Solicitud bloqueada por WAF | Baja | New | IP autorizada, `Blocked`, regla personalizada, TransactionId |
| LAB-P08 - Cambio Kubernetes | Baja | New | ConfigMap `soc-l2-p08`, usuario de prueba, respuesta 201 |

No son capturas ni resultados del tenant. El estado inicial puede variar por automatización. Tras investigar, cerrar con la clasificación disponible de actividad benigna/prueba autorizada y registrar el motivo; no etiquetar como ataque real.

> **Implementado en Terraform (opt-in).** [sentinel.tf](../sentinel.tf) despliega, con `enable_sentinel_analytics`, 13 reglas programadas `LAB-Pxx` (P02, P15, P04B con severidad High; P03, P05, P07, P08, P09, P10, P11, P12, P13, P14 con severidad Medium; las severidades se limitan a High/Medium por el filtro de prioridad 15–100 de Defender XDR) con su mapeo de entidades y una regla de automatización. Con `enable_sentinel_playbooks` se añaden dos playbooks (enriquecer comentario y etiquetar) que la automatización ejecuta sobre los incidentes `LAB-`. Las reglas P01, P04 y P06 de esta tabla siguen siendo propuestas sin código. **Si hay diferencias de severidad, ventana o frecuencia entre esta tabla y `sentinel.tf`, prevalecen las reglas implementadas.** Ver la sección «Contenido de Sentinel» del [README de Terraform](../README.md). Las rutas del conector de los playbooks están pendientes de verificar en el portal.

## 8. Workbook y vigilancia de cobertura

Paneles propuestos:

1. **Inventario esperado frente a recibido:** recurso, fuente, tabla, propietario, criticidad y última prueba exitosa. Usar IDs completos y normalizados para recursos; tratar nombres de host como otra clave.
2. **VM:** P01 como tabla de estado y evolución de Heartbeat.
3. **Seguridad:** fallos Windows por cuenta, eventos Syslog, lecturas/denegaciones de Key Vault, cambios Kubernetes y cambios ARM.
4. **Web:** solicitudes y estados HTTP de App Service. Gateway/WAF y correlación por transacción no aplican al despliegue actual.
5. **Operación de Sentinel:** fallos en `SentinelHealth`, cambios de reglas en `SentinelAudit` e incidentes LAB.
6. **Costo:** volumen ingerido por tabla, tendencias y alertas presupuestarias.

Consulta de volumen facturable registrado por tabla, no de costo final:

```kql
Usage
| where TimeGenerated > ago(24h)
| where IsBillable == true
| summarize VolumenMB = sum(Quantity) by DataType, QuantityUnit
| order by VolumenMB desc
```

Confirmar `QuantityUnit` antes de interpretar o convertir unidades. Facturación depende de planes, beneficios y fuentes; esta suma no equivale a una factura.

Para cada fuente de actividad esporádica, acordar un evento benigno periódico o revisión de configuración: la ausencia de `AZKVAuditLogs`/WAF no prueba desconexión si nadie accedió o no hubo bloqueos. Salud de conectores tampoco valida todas las rutas directas de diagnóstico.

> **Implementado en Terraform (opt-in).** Con `enable_sentinel_analytics`, [sentinel.tf](../sentinel.tf) publica el workbook `SOC L2 Lab - Eventos de seguridad generados` ([files/soc-workbook.json](../files/soc-workbook.json)) con paneles por prueba. Con `enable_sentinel_notebooks`, [sentinel_notebooks.tf](../sentinel_notebooks.tf) crea un workspace de Azure ML y una compute instance para los notebooks de caza ([SOC-L2-Eventos.ipynb](../notebooks/SOC-L2-Eventos.ipynb) y [SOC-L2-Caza.ipynb](../notebooks/SOC-L2-Caza.ipynb)), y [SOC-L2-Analisis-Logs.ipynb](../notebooks/SOC-L2-Analisis-Logs.ipynb), que se suben automáticamente con `terraform_data.upload_notebooks` (requiere Azure CLI). La compute instance factura mientras está encendida: detenerla al terminar.

## 9. Evidencia y criterios de aceptación

Por ejecución registrar:

| Campo | Contenido |
| --- | --- |
| Prueba y autorización | P01–P09, responsable y ventana acordada |
| Origen | Workspace, recurso, identidad e IP sin secretos |
| Generación | Hora UTC y marcador; evidencia de la acción benigna |
| Ingesta | Tabla, primer TimeGenerated, hora de recepción si existe y resultado KQL |
| Detección | Regla/versión, última ejecución, alertas e ID de incidente si aplica |
| Investigación | Entidades correctas, detalles y clasificación |
| Limpieza | Objetos/configuración temporal retirados y estado restaurado |

Criterios:

- **Ingesta aprobada:** la acción esperada aparece en su tabla y coincide en recurso, ventana y marcador/identidad; en P01 aparecen ambas VM.
- **Detección aprobada:** la consulta satisface el umbral y la regla produce alerta/incidente según su configuración. P05 es solo ingesta salvo que se añada una regla.
- **Cobertura incompleta:** tabla inexistente, recurso ausente del inventario o falta de evidencia. No reportar “todo monitoreado” solo porque haya Heartbeat.
- **Cierre:** limpieza confirmada y documentación de retrasos/fallos. La aceptación final requiere ejecutar estas pruebas con autorización; este archivo no acredita un despliegue.

## 10. Referencias oficiales

- [Conexión de fuentes Azure, Windows y Microsoft a Sentinel](https://learn.microsoft.com/azure/sentinel/connect-azure-windows-microsoft-services).
- [Salud y auditoría de Sentinel](https://learn.microsoft.com/azure/sentinel/enable-monitoring).
- [Auditoría de línea de comandos y evento 4688](https://learn.microsoft.com/windows-server/identity/ad-ds/manage/component-updates/command-line-process-auditing).
- [Esquema AGWFirewallLogs](https://learn.microsoft.com/azure/azure-monitor/reference/tables/agwfirewalllogs) y [AGWAccessLogs](https://learn.microsoft.com/azure/azure-monitor/reference/tables/agwaccesslogs).
- [Esquema AppServiceHTTPLogs](https://learn.microsoft.com/azure/azure-monitor/reference/tables/appservicehttplogs).
- [Esquema AZKVAuditLogs](https://learn.microsoft.com/azure/azure-monitor/reference/tables/azkvauditlogs).
- [Esquema AKSAuditAdmin y exclusión de get/list](https://learn.microsoft.com/azure/azure-monitor/reference/tables/aksauditadmin).
- [VNet flow logs: destino, requisitos y limitaciones](https://learn.microsoft.com/azure/network-watcher/vnet-flow-logs-overview).
- [Retirada y migración de NSG flow logs](https://learn.microsoft.com/azure/network-watcher/nsg-flow-logs-migrate).

Se consultó también el catálogo público de skills Azure: `azure-kusto`, del plugin `azure`, cubre consultas KQL y ya está disponible en este entorno; no requiere instalación adicional ni implica que las consultas se hayan ejecutado.
