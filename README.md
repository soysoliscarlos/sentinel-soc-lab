# Laboratorio SOC L2: Terraform para Azure

> **Repositorio oficial de GitHub:** [https://github.com/soysoliscarlos/sentinel-soc-lab](https://github.com/soysoliscarlos/sentinel-soc-lab)

Guía operativa propuesta: [cobertura de Sentinel y pruebas controladas](../Research/Sentinel%20-%20Cobertura%20y%20pruebas%20del%20laboratorio.md), con fuentes pendientes, consultas KQL y ejemplos de incidentes. No añade infraestructura ni ejecuta pruebas sobre Azure.

## Alcance confirmado

Código de infraestructura para un laboratorio en `eastus2`. El despliegue base fue iniciado por el usuario; Application Gateway/WAF se ha retirado del código por solicitud del usuario. Este cambio no ejecuta eliminaciones en Azure ni simulaciones. La validación local no demuestra disponibilidad regional, permisos, cuotas ni llegada real de logs.

| Componente | Configuración inicial | Telemetría al workspace de Sentinel |
| --- | --- | --- |
| Ubuntu 22.04 LTS | D2s_v6, clave SSH, IP pública Standard estática | AMA + DCR: `Syslog` de autenticación, daemon, kernel y sistema; `Heartbeat`. Con Ansible: Apache `local6` y PostgreSQL `local5`, preparado sin aplicar |
| Windows Server 2022 | D2s_v6, RDP, IP pública Standard estática | AMA + DCR: `SecurityEvent`, errores/advertencias de System y Application en `Event`; `Heartbeat`. Auditoría de logon/procesos y argumentos de 4688 preparada. Con Ansible: IIS `W3CIISLog` y auditoría/canales AD DS, sin aplicar |
| App Service Linux | Plan B1, endpoint HTTPS, sin aplicación desplegada | HTTP, consola, auditoría de publicación, restricciones IP y plataforma en tablas `AppService*` |
| AKS | Free, 2 nodos D4s_v6, Azure CNI Overlay, Entra ID y Azure RBAC | Container Insights: `ContainerLogV2`, `KubeEvents`, `KubePodInventory`; diagnósticos: `AKSAuditAdmin` y `AKSControlPlane`. Se añade `guard` al código, aún sin aplicar |
| Log Analytics | PerGB2018, 30 días, umbral de 1 GB/día, autenticación local deshabilitada | Workspace único para todos los orígenes |
| Microsoft Sentinel | Onboarding dedicado sobre el workspace | Datos consultables; no incluye reglas analíticas ni playbooks |
| Key Vault Standard | Private Endpoint y DNS privado; endpoint público restringido a `admin_source_cidr`, con RBAC | Auditoría `AuditEvent` hacia `AZKVAuditLogs` |
| Azure Activity | Diagnóstico de la suscripción, ocho categorías | `AzureActivity`, incluye recursos ajenos al laboratorio dentro de la misma suscripción |

**Cambio confirmado durante el diseño:** se sustituyó el perfil inicial de un nodo D2 por dos nodos D4s_v5 (luego D4s_v6) para respetar los requisitos vigentes del pool de sistema AKS: mínimo dos nodos y SKU de al menos 4 vCPU/4 GB, sin serie B. Free solo se refiere al nivel de administración del clúster, no a los nodos ni al resto de recursos.

**Ajuste tras el primer apply (2026-10-22):** en la suscripción destino, eastus2 devuelve `NotAvailableForSubscription` para las series B y Dv5 (las VM fallaron con `SkuNotAvailable` y AKS rechazó D4s_v5). Las VM pasan a `Standard_D2s_v6` y AKS a `Standard_D4s_v6`, que sí están disponibles salvo en la zona 2 (el código no fija zonas). La familia Dsv6 tiene cuota de 350 vCPU y el límite regional es de 65 vCPU; el stack usa 12 (+4 durante actualizaciones de AKS). Comprobar antes de cambiar tamaños con `az vm list-skus --location eastus2 --size <SKU> --all -o table` y `az vm list-usage --location eastus2 -o table`.

Terraform administra infraestructura, identidades, roles, agentes AMA y recolección. Cloud-init garantiza `rsyslog` en Ubuntu. Una extensión Custom Script configura auditoría de logon/procesos Windows mediante [Configure-WindowsAudit.ps1](scripts/Configure-WindowsAudit.ps1), pendiente de aplicar. [Ansible invocado desde Terraform](Ansible/README.md) instala IIS y un bosque AD `lab.example.test` en Windows, y Apache/PostgreSQL en Ubuntu. `enable_ansible` conserva `false` como valor por defecto, pero **está activado en las entradas del laboratorio; no se ejecutó contra Azure en este cambio**. Su preparación SSH se integra en la misma extensión Windows, preservando la auditoría.

Tras instalar y verificar los servicios, Ansible configura sus logs y Terraform amplía las DCR existentes hacia el mismo workspace: IIS W3C, auditoría/canales AD DS, archivos Apache por rsyslog y PostgreSQL por Syslog. **SQL completo autorizado mediante `log_statement='all'`: puede registrar secretos y datos personales y aumentar mucho la ingesta.** No se deshabilitan la cuota ni la retención existentes; revisar [rutas, límites y consultas de verificación](Ansible/README.md#telemetría-y-referencias). Quedan fuera Sysmon, las políticas de auditoría no declaradas, aplicaciones, workloads Kubernetes y simulaciones. Defender for Servers, las reglas de detección y las hunting queries son opt-in y se describen en la sección «Contenido de Sentinel».

No se crean conectores heredados de Azure Activity ni agentes MMA/OMS en las VM. El bloque Terraform `oms_agent` es el nombre conservado por AzureRM para el complemento de monitoreo AKS con autenticación por identidad administrada; se configura además su DCR y asociación explícita. El onboarding no instala soluciones de Content Hub ni configura conectores de Entra/Microsoft 365.

### Creación opcional de componentes

Los cuatro interruptores booleanos de [terraform.tfvars](terraform.tfvars) conservan `true` por defecto:

```hcl
create_app_service = true
create_linux_vm    = true
create_windows_vm  = true
create_aks         = true
```

Cada `false` excluye el componente y sus dependencias exclusivas: plan de App Service; IP, NIC, NSG, credenciales, extensiones y DCR de cada VM; subred, identidad, roles y Container Insights de AKS. La subred de VM se conserva mientras haya al menos una VM habilitada. Los outputs del componente desactivado son `null` (Terraform no los muestra).

Por decisión confirmada, `enable_ansible = true` **requiere ambas VM habilitadas**; la validación rechaza cualquier otra combinación. Para omitir una VM, establecer también `enable_ansible = false`. Los servicios compartidos (grupo, VNet, Key Vault con Private Endpoint/DNS, Log Analytics, Sentinel y Azure Activity) permanecen y pueden generar cargos.

**Un `false` no pausa un recurso existente: Terraform propondrá eliminarlo en el siguiente plan/apply.** Revisar costos, permisos, pérdida de datos y el plan antes de aplicar. [moved.tf](moved.tf) migra las direcciones originales a las instancias condicionales `[0]`, evitando reemplazos causados únicamente por esta refactorización si el componente sigue habilitado. No modifica directamente el estado ni se ha aplicado contra Azure.

### Generación de logs al final del despliegue

[log_generation.tf](log_generation.tf) define `terraform_data.log_generation`, que ejecuta [Invoke-SocLabLogGeneration.ps1](scripts/Invoke-SocLabLogGeneration.ps1) con `local-exec` como **último paso del apply**. Depende de:

- Ansible y las extensiones AMA, incluida la auditoría Windows.
- Las tres asociaciones DCR (Linux, Windows y AKS).
- Los diagnostic settings de App Service, AKS, Key Vault y Activity Log.
- El onboarding de Sentinel y los roles de AKS y Key Vault.

Que los recursos existan no garantiza que ya envíen datos. Por eso el script espera primero el `Heartbeat` de las VM presentes y el `KubePodInventory` de AKS si existe y está seleccionado, hasta `log_generation_wait_minutes` (30). Después espera `log_generation_initial_delay_seconds` (300) para los diagnostic settings recién creados. Si una fuente no responde a tiempo, falla sin generar actividad. Los grupos sin recurso se informan como `Omitida`; `WebServers` requiere ambas VM y `Arm` usa la VM Linux. P07 lista los metadatos de secretos y solo lee `linux-ssh-public-key` si existe; sin Linux genera únicamente SecretList y SecretGet fallido sobre un nombre inexistente, sin leer contraseñas.

Cada ejecución produce actividad variada y benigna: en Windows varios 4625 con usuarios inexistentes (P02), varios procesos 4688 (P03) y el ciclo de vida de cuentas/grupos de dominio desechables (P15: 4720/4722/4724/4725/4726/4727/4728/4729/4730/4732/4733/4738 y 4776), creados y eliminados dentro del mismo paso; en Linux `logger` en varias facilidades (P04) y SSH/`su` fallidos con usuarios inexistentes (P04B). P15 requiere que la VM Windows sea controlador de dominio (módulo `ActiveDirectory`).

| Variable | Valor por defecto | Uso |
| --- | --- | --- |
| `enable_log_generation` | `false` (activada en `terraform.tfvars`) | Opt-in de la simulación |
| `log_generation_tests` | `["All"]` | `Windows`, `Linux`, `WebServers`, `AppService`, `KeyVault`, `Arm`, `Aks` |
| `log_generation_verify` | `true` | Consulta cada marcador; la ingesta pendiente se informa y no falla el apply |
| `log_generation_trigger` | `"inicial"` | Cambiarlo repite las pruebas en el siguiente apply |

Requisitos del equipo que ejecuta Terraform:
- Azure CLI con sesión iniciada en la suscripción.
- Windows PowerShell.
- La IP de `admin_source_cidr`, que necesitan HTTP, Key Vault y la API de AKS.

Se ejecuta solo al crearse el recurso, o cuando cambian el disparador, las pruebas, el script o una asociación/diagnóstico. Con un error de generación, el apply falla y Terraform repite el recurso en el siguiente apply. La prueba P09 cambia una etiqueta fuera de Terraform y la restaura en el mismo paso, por lo que no deja deriva.

## Contenido de Sentinel

Además del onboarding, el repositorio puede desplegar contenido de Sentinel que **muestra los eventos que genera el script** ([sentinel.tf](sentinel.tf), [sentinel_playbooks.tf](sentinel_playbooks.tf), [sentinel_notebooks.tf](sentinel_notebooks.tf)). Todo es **opt-in** y está desactivado por defecto; `terraform.tfvars` lo activa para el taller.

| Interruptor | Defecto | Qué crea | Requisitos |
| --- | --- | --- | --- |
| `enable_sentinel_analytics` | `false` (activado en `terraform.tfvars`) | 13 reglas analíticas programadas `LAB-Pxx`, un workbook, 2 hunting queries (HUNT-01/HUNT-02, en `sentinel_hunting.tf`) y una regla de automatización | Onboarding de Sentinel |
| `enable_sentinel_playbooks` | `false` (activado en `terraform.tfvars`) | 2 playbooks (Logic Apps) y sus asignaciones de rol | Requiere `enable_sentinel_analytics`; RP `Microsoft.Logic` y `Microsoft.Web` |
| `enable_sentinel_notebooks` | `false` (activado en `terraform.tfvars`) | Workspace de Azure ML (storage, Key Vault, App Insights) y una compute instance | RP `Microsoft.MachineLearningServices` |

Como el proveedor usa `resource_provider_registrations = "none"`, antes de un apply con playbooks o notebooks hay que registrar manualmente los RP:

```powershell
az provider register --namespace Microsoft.Logic
az provider register --namespace Microsoft.Web
az provider register --namespace Microsoft.MachineLearningServices
```

### Reglas analíticas y workbook

Cada regla consulta el marcador de una prueba y crea un incidente `LAB-Pxx`. Los nombres de regla, workbook y regla de automatización son GUID (`random_uuid`), como exige la API. Están configuradas con frecuencia `PT5M` (evaluación cada 5 minutos) y severidades `High` / `Medium` para que los incidentes tengan un *Priority Score* $\ge 15$ y aparezcan de forma directa en el portal unificado de Microsoft Defender XDR (**Casos / Incidentes**) sin ser excluidos por el filtro predeterminado `Priority score: 15 - 100`.

| Regla | Severidad | Prueba y marcador que detecta |
| --- | --- | --- |
| `LAB-P02 - Fallos de autenticacion Windows (Fuerza Bruta)` | High | 4625 con cuentas inexistentes `soc-l2-p02-*` ($\ge 2$ intentos) |
| `LAB-P15 - Gestion anomala de cuentas y grupos AD` | High | Altas/cambios/bajas de cuentas y grupos desechables `SOCp15/SOCg15` |
| `LAB-P03 - Ejecucion de procesos sospechosos en Windows` | Medium | 4688 con la línea de comandos `SOC-L2-P03` |
| `LAB-P04B - Fuerza bruta SSH y su en Linux` | High | SSH y `su` con usuarios inexistentes `socp04*` |
| `LAB-P05 - Escaneo web y reconocimiento en App Service` | Medium | Rutas/métodos sospechosos con User-Agent `SOC-L2-Lab` |
| `LAB-P07 - Acceso no autorizado o denegado en Key Vault` | Medium | Lectura fallida del secreto inexistente `soc-l2-p07` |
| `LAB-P08 - Modificaciones administrativas en Kubernetes` | Medium | Creación de objetos en el namespace `soc-l2-p08` (auditoría admin de AKS) |
| `LAB-P09 - Modificacion sospechosa de etiquetas ARM` | Medium | Modificación no autorizada de etiqueta `SOCPrueba` en `AzureActivity` |
| `LAB-P10 - Evento de advertencia en pods de AKS` | Medium | Eventos Warning de Kubernetes en `KubeEvents` por pods de prueba |
| `LAB-P11 - Peticion HTTP anomala en servidor Apache` | Medium | Solicitudes HTTP marcadas hacia Apache en `Syslog local6` |
| `LAB-P12 - Peticion HTTP sospechosa en servidor IIS` | Medium | Sondeo o acceso web marcado en `W3CIISLog` |
| `LAB-P13 - Fallo de autenticacion en base de datos PostgreSQL` | Medium | Intentos fallidos de conexión con usuario inválido en `Syslog local5` |
| `LAB-P14 - Evento sospechoso en Application Log de Windows` | Medium | Evento de advertencia generado por `SOC-L2-Lab` en `Event` |

El workbook `SOC L2 Lab - Eventos de seguridad generados` ([files/soc-workbook.json](files/soc-workbook.json)) agrupa paneles por prueba con un parámetro de rango de tiempo. Se abre en **Sentinel > Workbooks > Mis workbooks** o **Azure Monitor > Workbooks**.

### Playbooks y automatización

Se despliegan como plantillas ARM ([files/playbook-enrich-comment.json](files/playbook-enrich-comment.json) y [files/playbook-tag-triage.json](files/playbook-tag-triage.json)) porque la conexión con identidad administrada no es expresable con `azurerm_api_connection`:

- **enrich** agrega un comentario de enriquecimiento al incidente.
- **triage** marca el incidente como `Active` y añade las etiquetas `SOC-L2-Lab` y `Taller`.

La regla de automatización `LAB - Etiquetar y enriquecer incidentes del taller` filtra por título que contiene `LAB-`, añade la etiqueta `SOC-L2-Lab` (orden 1) y ejecuta los dos playbooks (orden 2 y 3). Asignaciones de rol creadas:

- Cada playbook (su identidad administrada): **Microsoft Sentinel Responder** sobre el grupo.
- El service principal de Sentinel (`Azure Security Insights`): **Microsoft Sentinel Automation Contributor** sobre el grupo, necesario para que la regla invoque los playbooks.

> **Pendiente de verificar en el portal:** las rutas del conector (`/Incidents/Comment`, `PUT /Incidents`) y la forma de `tagsToAdd` siguen la convención de playbooks exportados, pero no están verificadas contra este tenant. Tras el primer apply conviene abrir cada Logic App, autorizar la conexión `azuresentinel` y validar que las acciones se ejecutan, ajustando el JSON si el portal lo requiere.

### Notebooks (Azure Machine Learning)

[sentinel_notebooks.tf](sentinel_notebooks.tf) crea un workspace de Azure ML con su storage, Key Vault y Application Insights, más una compute instance (`Standard_DS2_v2` por defecto, variable `sentinel_notebook_compute_size`). La identidad administrada de la compute instance recibe **Log Analytics Reader** sobre `soc-l2-law` para que los notebooks consulten con `DefaultAzureCredential`.

Los tres notebooks ([SOC-L2-Eventos.ipynb](notebooks/SOC-L2-Eventos.ipynb), [SOC-L2-Caza.ipynb](notebooks/SOC-L2-Caza.ipynb) y [SOC-L2-Analisis-Logs.ipynb](notebooks/SOC-L2-Analisis-Logs.ipynb)) se suben automáticamente al file share del workspace mediante `terraform_data.upload_notebooks` (que usa `az storage file upload`, por lo que requiere Azure CLI autenticado). Si la subida falla, pueden cargarse a mano en **Azure ML Studio > Notebooks**.

### Defender for Servers y hunting queries

- [defender.tf](defender.tf): con `enable_defender_for_servers` activa Defender for Servers (subplan P1/P2 según variable), la integración WDATP (`azurerm_security_center_setting`) y las extensiones MDE.Windows / MDE.Linux. **El alcance es toda la suscripción y genera costo**; revisar antes de aplicar.
- [sentinel_hunting.tf](sentinel_hunting.tf): 2 saved searches (HUNT-01 y HUNT-02) para caza manual, condicionadas a `enable_sentinel_analytics`.

> **Costo:** la compute instance **factura por hora mientras está encendida** y no tiene apagado automático en el provider. Detenerla manualmente en el portal o programar un apagado cuando no se use. Las cuotas de la familia de VM deben validarse antes de cambiar el tamaño.



Revisión de solo lectura del 2026-10-22 por la noche, con registros hasta aproximadamente **2026-10-23 02:14 UTC**. Se verificaron el grupo `soc-l2-rg`, el grupo administrado `MC_soc-l2-rg_soc-l2-aks_eastus2` y el workspace `soc-l2-law`; Sentinel tiene onboarding `default`. No se aplicaron cambios ni se generaron eventos de prueba.

- Ambas extensiones AMA están en `Succeeded`, con DCR/asociación correcta y destino en el mismo workspace. Se comprobó el recurso de origen de los eventos, no solo el nombre de la tabla.
- AKS está `Running`/`Succeeded`, con Container Insights habilitado, autenticación administrada y DCR/asociación correcta. Reciben Heartbeat los dos nodos.
- Diagnósticos de App Service, Key Vault y AKS apuntan al workspace con destino `Dedicated`. Activity Log de suscripción envía las ocho categorías esperadas.
- El workspace conserva 30 días, cuota de 1 GB/día y estado de ingesta `RespectQuota` durante la revisión. Esto no garantiza que no alcance la cuota más adelante.

| Origen | Evidencia real en las últimas 24 h | Conclusión y límite |
| --- | --- | --- |
| Ubuntu `soc-l2-linux` | `Heartbeat` y `Syslog` con su `_ResourceId` | Conexión e ingesta comprobadas; no equivale a auditd de procesos/archivos |
| Windows `soc-l2-windows` / `soc-win` | `Heartbeat`, 253 `SecurityEvent` y 2 `Event` | Conexión e ingesta comprobadas. Los 221 eventos 4688 consultados no incluyen `CommandLine`; se prepara corrección |
| App Service `soc-l2-web` | 56 HTTP, 99 consola, 32 restricciones IP y 270 plataforma | Cuatro rutas comprobadas; auditoría de publicación está configurada, pero sin eventos: no se acredita su entrega extremo a extremo |
| AKS `soc-l2-aks` | 12 421 `AKSAuditAdmin`, 394 control plane, 27 `KubeEvents`, 336 `KubePodInventory`, Heartbeat de dos nodos | Ingesta comprobada de esas fuentes. `ContainerLogV2` sin eventos; inventario reciente solo de `kube-system`, cuyos stdout/stderr se excluyen por defecto salvo configuración adicional |
| Key Vault `soc-l2-kv01` | 7 `AZKVAuditLogs` | Auditoría con ID de vault correcto; no se leyeron secretos para esta revisión |
| Recursos de soporte y grupo administrado AKS | `AzureActivity` con operaciones de ambos grupos | Cobertura de cambios ARM para VNet, NSG, NIC, IP, discos, DNS privado, Private Endpoint, identidades, plan y recursos administrados; no es cobertura de tráfico o de contenido |

Los conteos son una instantánea de una consulta, no umbrales de salud ni garantía de cobertura futura. No se ejecutó una publicación ni se desplegó un workload para forzar eventos. Se necesita una prueba autorizada con una aplicación/contenedor no sistémico para validar las rutas silenciosas.

**Cambios preparados, no aplicados:**

1. Se incorpora la categoría AKS `guard` a los diagnósticos, para no omitir esa señal de autenticación. No activa el conector de Entra ID del tenant ni incluye lecturas `get/list` de Kubernetes.
2. La extensión `ConfigureWindowsAudit` habilita Logon y Process Creation por GUID independientes del idioma, prioriza subcategorías avanzadas y activa `ProcessCreationIncludeCmdLine_Enabled`. El script falla explícitamente si `auditpol` o el registro fallan. No habilita Sysmon, Script Block Logging ni todas las políticas de cuentas.
3. [Pruebas Terraform](tests/lab.tftest.hcl) verifican destinos, asociaciones, categorías completas, streams/fuentes, esquemas dedicados y la extensión. La ampliación de Ansible/logs lleva la validación local a **16 pruebas aprobadas**, con proveedores simulados, además de `terraform fmt -check` y `terraform validate`. Los scripts Windows se comprueban con comandos simulados; no acredita ingesta de los servicios recién configurados.

La extensión ejecuta la configuración dentro de la VM como SYSTEM al aplicar Terraform; no necesita Ansible ni un servicio nuevo. **Los argumentos de procesos quedarán en texto plano en los logs**, por lo que no deben contener secretos. Revisar acceso al workspace y posibles GPO que sobrescriban la política. Eliminar la extensión no revierte las políticas; cualquier reversión debe ser explícita. La nueva categoría puede incrementar ingesta y costo aunque no se habilite ningún plan de pago adicional.

Para verificar posteriormente la corrección Windows, sin generar nuevos eventos:

```kusto
SecurityEvent
| where TimeGenerated > ago(30m)
| where Computer startswith "soc-win" and EventID == 4688
| summarize Procesos=count(), ConArgumentos=countif(isnotempty(CommandLine))
```

Acotar la ventana al periodo posterior a aplicar la extensión. Cero eventos no prueba el resultado; si hay procesos nuevos pero ninguno tiene argumentos, investigar la política y el XML local antes de dar la corrección por validada.

**Fuera de esta cobertura:** no hay flujos de red/paquetes, Entra ID del tenant, Defender, Sysmon ni auditoría completa de lecturas AKS. Las métricas de los recursos no se exportan indiscriminadamente a Log Analytics. Ningún diagnóstico por recurso puede sustituir estas fuentes. Se encontró una política residual `soc-l2-waf` en Azure, pero no un Application Gateway: no demuestra protección ni telemetría WAF y no se modifica en esta revisión.

## Red y acceso

- VNet `10.20.0.0/16`, subred de VM `10.20.1.0/24` y subred AKS `10.20.2.0/24`. Pods `10.244.0.0/16`, servicios `10.30.0.0/16`.
- Cada NIC de VM tiene su propio NSG: por defecto solo SSH o RDP desde `admin_source_cidr`; se deniega todo otro ingreso, también lateral desde la VNet. Con `enable_ansible = true` se permite además SSH Windows y HTTP de ambas VM desde ese mismo CIDR, y Windows recibe la IP privada fija `10.20.1.10`. No se exponen PostgreSQL ni puertos AD. El firewall del SO sigue aplicando.
- `admin_source_cidr` es obligatorio, IPv4 público, entre /24 y /32; se recomienda la IP de salida real del administrador en /32. `10.10.0.0/16` se descartó porque no identifica el origen público de una conexión a Internet.
- La API de AKS usa ese mismo CIDR, con cuentas locales deshabilitadas. El nodo no tiene IP pública individual; AKS usa Standard Load Balancer para salida.
- App Service tiene acceso público directo por HTTPS, sin Application Gateway, WAF, Private Endpoint ni integración VNet. SCM/Kudu no hereda restricciones de una subred del Gateway.
- AMA y AKS acceden a los endpoints públicos de Azure Monitor. No bloquear salida a Entra ID, Azure Monitor, ARM, repositorios e infraestructura AKS; no hay Firewall, NAT Gateway ni Bastion adicionales.
- El workspace permite ingesta/consulta de red pública autenticada; no permite consultas anónimas. No hay AMPLS/Private Link.
- Key Vault tiene un Private Endpoint en `10.20.3.0/24` y la zona `privatelink.vaultcore.azure.net` vinculada a la VNet. Desde ella se usa el nombre normal del vault, resuelto a su IP privada. El endpoint público permanece habilitado solo para `admin_source_cidr`, con `default_action = "Deny"` y sin bypass de servicios Azure. Esta excepción no restringe el tráfico que entra por Private Endpoint: sigue siendo obligatorio autorizarlo mediante RBAC.

## Requisitos pendientes antes de desplegar

1. **Confirmar presupuesto y autorización del entorno.** Elegir preferentemente una suscripción exclusiva de laboratorio; Azure Activity y asignaciones RBAC tienen alcance fuera del grupo del laboratorio.
2. Terraform >= 1.9 y < 2, Azure CLI y proveedor AzureRM **5.10.0**, fijado en la configuración y en el lockfile. Esta configuración usa nombres de atributos de AzureRM 5; no copiar sin adaptar a AzureRM 4.
3. Contributor para crear recursos y diagnósticos, con alcance de suscripción para el diagnóstico Azure Activity; además User Access Administrator o Role Based Access Control Administrator para asignar roles. Owner cubre ambos. Se pueden usar permisos equivalentes más acotados si el administrador los prepara.
4. Registro previo de `Microsoft.Compute`, `Microsoft.Network`, `Microsoft.OperationalInsights`, `Microsoft.OperationsManagement`, `Microsoft.SecurityInsights`, `Microsoft.Insights`, `Microsoft.Web`, `Microsoft.ContainerService`, `Microsoft.ManagedIdentity` y `Microsoft.KeyVault`. El proveedor tiene `resource_provider_registrations = "none"`: no registra proveedores implícitamente.
5. Cuota y capacidad para dos VM D2s_v6 y dos nodos AKS D4s_v6 (más capacidad transitoria para actualización/rotación), discos e IP públicas. Revisar restricciones de nuevas suscripciones y políticas sobre IP públicas, SKUs y ubicaciones.
6. La identidad autenticada que ejecuta el proveedor AzureRM se obtiene automáticamente mediante `data.azurerm_client_config.current.object_id`. Recibe `Azure Kubernetes Service RBAC Cluster Admin` solo en este clúster y `Key Vault Secrets Officer` solo en el vault. Con Azure CLI será el usuario autenticado; con service principal, OIDC o identidad administrada será esa identidad, no el usuario humano que inició el pipeline. Mantener una identidad estable entre ejecuciones y revisar cambios de principal en el plan.
7. Terraform genera el par RSA de 4096 bits con TLS 4.4.2 y registra la pública mediante `azurerm_ssh_public_key`. Esa misma pública configura Ubuntu y se guarda como secreto `linux-ssh-public-key` en Key Vault. `azurerm_ssh_public_key` no genera claves por sí solo. La privada **queda en el estado** (decisión confirmada) y no se almacena en Key Vault. Random 3.9.1 genera la contraseña Windows de `socadmin` con 32 caracteres y al menos cuatro mayúsculas, cuatro minúsculas, cuatro números y cuatro símbolos. La misma contraseña configura la VM y se almacena en el secreto `windows-admin-password`. La contraseña **también queda en el estado**: `sensitive` oculta valores en salidas normales, **no los cifra en el estado ni en un plan guardado**.
8. Prefijo disponible globalmente para App Service; versiones AKS e imágenes disponibles en la región. Si se proporciona `kubernetes_version`, comprobar su soporte antes del plan.

Para comprobar proveedores existentes, después de autenticar y seleccionar la suscripción:

```powershell
az provider list --query "[?namespace=='Microsoft.Compute' || namespace=='Microsoft.Network' || namespace=='Microsoft.OperationalInsights' || namespace=='Microsoft.OperationsManagement' || namespace=='Microsoft.SecurityInsights' || namespace=='Microsoft.Insights' || namespace=='Microsoft.Web' || namespace=='Microsoft.ContainerService' || namespace=='Microsoft.ManagedIdentity' || namespace=='Microsoft.KeyVault'].{Namespace:namespace,Estado:registrationState}" -o table
az vm list-usage --location eastus2 -o table
az aks get-versions --location eastus2 -o table
```

Si faltan registros, un administrador debe registrarlos antes del despliegue. Las consultas de cuota no garantizan capacidad ni disponibilidad de una SKU.

## Costos y límites del laboratorio

**Presupuesto no confirmado. No hay una cotización validada para esta suscripción.** Antes de aprobar el despliegue, calcular horas de ejecución y tarifas regionales de:

- Dos VM D2s_v6, licencia Windows y discos administrados Standard.
- Dos nodos AKS D4s_v6, discos de nodos, Load Balancer, IP de salida y posible nodo temporal durante operaciones.
- Dos IP públicas de VM y tráfico de red.
- App Service B1 (se factura el plan aunque no haya aplicación).
- Key Vault Standard, operaciones, Private Endpoint (horas y datos) y zona/consultas de DNS privado.
- Ingesta y retención Log Analytics/Microsoft Sentinel. Azure Activity puede tener condiciones de ingesta gratuita; verificarlas en el modelo de precios de la suscripción.

El umbral diario de 1 GB **no es un límite de facturación garantizado**: puede superarse y no aplica igual a todos los tipos de datos. Al alcanzarse puede perderse telemetría y cobertura de detección. Los logs de autenticación y de AKS pueden producir mucho volumen. Se recoge `kube-audit-admin`, no `kube-audit` completo, para reducir ruido; las lecturas de API no quedan cubiertas por esa auditoría filtrada.

Crear un presupuesto/alertas de Cost Management antes de desplegar es una recomendación, no un recurso incluido. No asumir que detener las VM elimina costos: discos, IP, App Service y otros recursos pueden seguir facturando. Revisar también el grupo administrado `MC_` de AKS.

## Uso local y despliegue manual

Ejecutar desde este directorio. Los pasos de despliegue siguientes son instrucciones para una ejecución futura autorizada; no se ejecutaron al crear el código.

### Validación sin Azure

```powershell
terraform init -backend=false -input=false
terraform fmt -check -recursive
terraform validate
terraform test
```

Las pruebas usan proveedores mock y `command = plan`: no requieren login ni crean recursos. Validan el perfil, acceso, asociaciones de agentes/DCR, destino único de telemetría, generación/cableado de claves, red/RBAC de Key Vault y acceso HTTPS directo a App Service, además del rechazo de entradas peligrosas. No validan las API de Azure ni la ingesta real.

### Preparar entradas

Editar [terraform.tfvars](terraform.tfvars), que contiene explícitamente todos los SKU y tamaños: VM Linux/Windows, imágenes y discos de sistema, nivel/nodos/SO/balanceador de AKS, App Service, Key Vault, Log Analytics e IP públicas. Se mantienen los valores actuales; las variables conservan sus valores predeterminados para otros archivos de entradas. Los SKU de imágenes deben pertenecer al publisher/offer configurado en [compute.tf](compute.tf); cambiarlos puede reemplazar las VM. Ubuntu en AKS, balanceador Standard, IP públicas Standard y workspace PerGB2018 están restringidos mediante validación al perfil soportado. Otros cambios de SKU requieren comprobar compatibilidad, cuota, disponibilidad y costos, y revisar el plan antes de aplicar.

Verificar la suscripción, la identidad autenticada y que `admin_source_cidr` identifique la salida pública real del ejecutor (por ejemplo, una IP con `/32`). Ya no existen las variables `aks_admin_object_id` ni `linux_ssh_public_key`: quitarlas de cualquier `.tfvars` anterior; los roles se asignan al ejecutor y la clave se genera durante el despliegue autorizado.

Si ya existe una VM con una clave propia, revisar el cambio de clave en el plan y conservar el acceso anterior hasta completar la transición. La generación TLS permanece estable mientras se conserve el estado; reemplazar el recurso TLS rota la clave y requiere revisar cómo AzureRM aplicará el cambio a la VM.

No colocar secretos en este directorio sincronizado con OneDrive. **Antes de plan/apply configurar un backend remoto aprobado con cifrado, RBAC, bloqueo y acceso restringido**, o ejecutar desde una ubicación local no sincronizada y protegida. Por defecto Terraform usaría estado local: este repositorio no crea ni presupone un backend. Conservar `.terraform.lock.hcl`; excluir estados, planes y archivos `.tfvars` de cualquier repositorio.

### Autenticar, planificar y revisar

Una vez preparado el backend elegido y confirmados presupuesto/permisos:

```powershell
az login
az account set --subscription "<subscription-id>"
terraform init
terraform validate
if ($LASTEXITCODE -ne 0) { throw "terraform validate fallo" }
terraform plan -out=lab.tfplan
if ($LASTEXITCODE -ne 0) { throw "terraform plan fallo" }
```

Revisar el plan y aprobar explícitamente el costo y las modificaciones. El plan guardado contiene datos sensibles; protegerlo y eliminarlo tras su uso. Solo entonces ejecutar manualmente:

```powershell
terraform apply .\lab.tfplan
terraform output
```

No usar `-auto-approve`. Para AKS, instalar `kubectl` y `kubelogin`, autenticarse como la identidad autorizada y obtener credenciales de usuario:

```powershell
az aks get-credentials --resource-group "<prefijo>-rg" --name "<prefijo>-aks"
kubelogin convert-kubeconfig -l azurecli
kubectl get nodes
```

No se exportan kubeconfig, contraseñas ni claves del workspace como outputs. La privada SSH sí tiene un output explícito sensible: `linux_ssh_private_key`. Para usar SSH, exportarla con `terraform output -raw linux_ssh_private_key` exclusivamente a un archivo protegido fuera de OneDrive, sin mostrarla en chats, logs ni repositorios; limitar sus permisos al usuario administrador. No es posible recuperarla desde Key Vault porque allí se almacena solo la pública. Las pruebas mock no generan un par real.

## Operación de Key Vault

- La contraseña Windows ya no es una entrada: retirar `windows_admin_password` de `.tfvars` anteriores y dejar de usar `TF_VAR_windows_admin_password`. Se genera al aplicar y se mantiene estable mientras no se reemplace `random_password.windows_admin`. No se utiliza `timestamp()` ni una rotación automática en cada apply.
- Para RDP, consultar `windows-admin-password` en Key Vault con una identidad autorizada desde la red permitida, preferentemente mediante el portal sin copiarla a logs o archivos. Terraform exporta únicamente `windows_admin_password_secret_id`, no el valor de la contraseña.
- Si la VM ya existe, el primer plan de esta migración cambiará su contraseña; revisar y autorizar el cambio. No rotar el secreto por separado: para una rotación futura, planificar el reemplazo de `random_password.windows_admin` y revisar que la VM y el secreto se actualicen juntos. Guardar un secreto no modifica por sí solo la contraseña del sistema operativo. Si apply falla parcialmente, verificar qué pasos se completaron y reconciliar VM y vault antes de usar RDP.
- El ejecutor de Terraform recibe `Key Vault Secrets Officer` únicamente sobre este vault, para crear y mantener los secretos. Es la misma identidad que recibe administración RBAC de AKS, sin introducir un Object ID manual. El CIDR autoriza red, **no identidad**. Otros usuarios necesitan roles de datos explícitos; no se concede acceso de secretos a las VM automáticamente.
- Ejecutar plan/apply/refresh/destroy desde `admin_source_cidr` o desde una red con acceso al Private Endpoint y resolución DNS privada. Agentes CI con otra IP serán bloqueados. El acceso al plano ARM no garantiza acceso al plano de datos de secretos.
- El RBAC recién creado puede tardar en propagarse. Si Azure responde 403, revisar el error: `ForbiddenByFirewall` requiere corregir red/DNS/origen; una denegación RBAC requiere revisar identidad/rol y su propagación. Reintentar tras confirmar la causa, sin abrir el firewall ni introducir esperas ciegas.
- Consultar solo la pública después del despliegue con `az keyvault secret show --vault-name "<prefijo>-kv01" --name linux-ssh-public-key --query value -o tsv` (o usar el output `key_vault_name`). Dentro de la VNet, `Resolve-DnsName "<prefijo>-kv01.vault.azure.net"` debe resolver a la IP del output `key_vault_private_ip`. No se crea una VPN para el administrador.
- El nombre `${name_prefix}-${key_vault_name_suffix}` (por defecto `kv01`) debe ser globalmente único y cumplir las restricciones de Azure Key Vault (incluida la ausencia de guiones consecutivos); ajustar el prefijo o el sufijo si existe conflicto.
- Soft delete de 7 días está activo, pero purge protection está **deshabilitado** a propósito: `terraform destroy` purga los secretos y el vault, que dejan de ser recuperables y liberan el nombre de inmediato. Purge protection no puede desactivarse después de habilitarlo (el provider falla con *once Purge Protection has been Enabled it's not possible to disable it*).
- **Migración desde despliegues anteriores:** la primera versión creó `<prefijo>-kv` con purge protection. Ese vault nunca podrá purgarse. El cambio a `<prefijo>-kv01` hace que el siguiente `apply` lo **reemplace**: crea un vault nuevo sin protección, vuelve a escribir los secretos, el Private Endpoint, el rol y el diagnóstico, y borra el antiguo. El provider omite la purga del vault protegido y de sus secretos; Azure los elimina al cumplirse los 7 días. Revisar ese reemplazo en el plan antes de aplicarlo. Desde entonces, destroy elimina el vault por completo.
- Auditoría hacia el mismo workspace de Sentinel: consultar `AZKVAuditLogs | where TimeGenerated > ago(30m)`. Verificar generación e ingesta real después del despliegue.

## Verificación operativa después de un despliegue autorizado

> Generación automática de actividad: [Invoke-SocLabLogGeneration.ps1](scripts/Invoke-SocLabLogGeneration.ps1) ejecuta las pruebas P02–P15 de la [guía de cobertura](../Research/Sentinel%20-%20Cobertura%20y%20pruebas%20del%20laboratorio.md). Terraform la lanza al final del apply con `enable_log_generation` ([detalle](#generación-de-logs-al-final-del-despliegue)), o puede ejecutarse a mano. Usa `-WhatIf` para revisar el alcance sin generar actividad.

1. Comprobar ambas extensiones AMA con estado satisfactorio y la asociación de cada DCR. En Ubuntu comprobar `cloud-init status --wait` y `systemctl status rsyslog`.
2. Hacer un acceso administrativo normal autorizado a cada VM. Algunos eventos Windows, por ejemplo 4688, requieren habilitar previamente la política de auditoría correspondiente; incluirlos en un XPath no habilita esa auditoría ni instala Sysmon.
3. Acceder al endpoint HTTPS de App Service. Sin aplicación propia no se esperan logs de negocio y puede no haber logs de consola. No interpretar el endpoint aprovisionado como aplicación desplegada.
4. Comprobar nodos y pods de monitoreo AKS. No hay workloads de usuario: `ContainerLogV2` dependerá de contenedores que emitan stdout/stderr y de la configuración del agente. Inventario/eventos se recogen con intervalo de 5 minutos; no es un límite de gasto ni una tasa universal de logs.
5. Abrir los Logs del workspace de Sentinel y, después del tiempo de ingesta, ejecutar cada consulta de forma independiente:

```kusto
Heartbeat
| where TimeGenerated > ago(30m)
| summarize Ultimo=max(TimeGenerated) by Computer, OSType
```

```kusto
Syslog
| where TimeGenerated > ago(30m)
| summarize Eventos=count(), Ultimo=max(TimeGenerated) by Computer, Facility
```

```kusto
SecurityEvent
| where TimeGenerated > ago(30m)
| summarize Eventos=count() by Computer, EventID
```

```kusto
Event
| where TimeGenerated > ago(30m)
| summarize Eventos=count() by Computer, EventLog
```

```kusto
AppServiceHTTPLogs
| where TimeGenerated > ago(30m)
| summarize Solicitudes=count() by _ResourceId
```

```kusto
KubePodInventory
| where TimeGenerated > ago(30m)
| summarize Ultimo=max(TimeGenerated) by ClusterName, Namespace
```

```kusto
ContainerLogV2
| where TimeGenerated > ago(30m)
| summarize Registros=count() by PodNamespace, PodName
```

```kusto
AKSAuditAdmin
| where TimeGenerated > ago(30m)
| summarize Operaciones=count() by _ResourceId
```

```kusto
AKSControlPlane
| where TimeGenerated > ago(30m)
| summarize Registros=count() by Category
```

```kusto
AzureActivity
| where TimeGenerated > ago(1h)
| summarize Operaciones=count() by CategoryValue, ResourceGroup
```

Una tabla puede no existir hasta recibir el primer registro; una consulta vacía o con error de tabla inexistente **no confirma** que la integración funcione. Revisar generación de eventos, salida de red, identidad, DCR/asociación, diagnósticos, cuota diaria y latencia. La habilitación de Sentinel no crea detecciones: esa configuración requiere otro alcance.

### Retirada de Application Gateway y WAF

Por decisión del usuario, el stack ya no incluye Application Gateway, política WAF, su subred dedicada, NSG, IP pública ni diagnóstico. App Service vuelve al acceso público directo por HTTPS, sin protección WAF; SCM/Kudu deja de heredar la restricción a la subred retirada. Se conservan TLS mínimo 1.2 y autenticación básica de publicación deshabilitada.

Si estos recursos ya se desplegaron y siguen en el estado, generar y revisar un plan nuevo: Terraform propondrá eliminarlos y actualizar las restricciones de App Service. No usar `terraform destroy`, porque eliminaría todo el laboratorio, ni quitar recursos del estado manualmente. El retiro en Azure solo ocurre al aplicar el plan autorizado y puede interrumpir conexiones existentes. Usar el output `app_service_url` como endpoint. No reutilizar planes guardados anteriores.

### Container Insights: identidad vacía del complemento

Con `msi_auth_for_monitoring_enabled = true`, Azure puede devolver `oms_agent_identity = []`. No se debe indexar esa lista ni asignar el rol `Monitoring Metrics Publisher` al complemento: la [autenticación administrada de Container Insights](https://learn.microsoft.com/azure/azure-monitor/containers/container-insights-authentication) ya no requiere ese rol. El agente conserva el workspace configurado y la DCR/asociación explícita; la asociación depende del clúster por su `target_resource_id`.

Si un apply anterior falló con `Invalid index` en `aks_monitor`, generar un plan nuevo y revisarlo antes de aplicar; no reutilizar un plan guardado anterior. No es necesario recrear el clúster ni deshabilitar el monitoreo por este error. Verificar después la ingesta con las consultas anteriores.

## Retirada

Solo tras autorización y conservación de cualquier evidencia necesaria:

```powershell
terraform plan -destroy -out=destroy.tfplan
terraform apply .\destroy.tfplan
```

La planificación de destrucción también necesita las variables obligatorias; la contraseña ya no se introduce manualmente.

La destrucción es **permanente** por configuración del bloque `features` en [providers.tf](providers.tf):

| Recurso | Comportamiento en destroy |
|---|---|
| Secretos de Key Vault | Se borran y se purgan (`purge_soft_deleted_secrets_on_destroy`). |
| Key Vault | Se borra y se purga (`purge_soft_delete_on_destroy`); requiere `purge_protection_enabled = false`. |
| Workspace de Log Analytics y Sentinel | Borrado permanente sin la retención de recuperación de 14 días (`permanently_delete_on_destroy`); los datos se pierden. |
| Discos de SO de las VM | Se eliminan con la VM (`delete_os_disk_on_deletion`). |
| AKS (incluido el grupo `MC_`), App Service, red, IPs, DNS privada, DCR, diagnósticos, roles y clave SSH | Se eliminan; no tienen soft delete. |

`recover_soft_deleted_*` está deshabilitado: si existe un vault o secreto borrado con el mismo nombre, `apply` falla en lugar de recuperarlo. Si se ejecuta destroy **antes** de aplicar la migración a `kv01`, el vault antiguo `<prefijo>-kv`, que tiene purge protection, quedará 7 días en soft delete sin poder purgarse. Requisitos para purgar:

- La identidad que ejecuta Terraform necesita `Microsoft.KeyVault/locations/deletedVaults/purge/action` a nivel de **suscripción** (p. ej. Contributor/Key Vault Contributor); un rol limitado al grupo de recursos no basta. La purga de secretos la cubre `Key Vault Secrets Officer`, que Terraform retira después de los secretos.
- Ejecutar destroy desde `admin_source_cidr` o la red privada, porque los secretos se purgan por el plano de datos.
- El grupo de recursos conserva `prevent_deletion_if_contains_resources` por defecto: si alguien creó recursos fuera de Terraform (p. ej. reglas de Sentinel desde el portal), destroy fallará al borrar el grupo en vez de eliminarlos sin control; eliminarlos o importarlos antes de reintentar. El diagnóstico de suscripción creado por este stack se elimina; no se deben modificar diagnósticos de terceros. Proteger y borrar de forma controlada los planes usados.

## Referencias verificadas para el diseño

- [Investigación de infraestructura](../Research/Infraestructura%20Azure%20Con%20Terraform.md).
- [Investigación de Sentinel](../Research/Configurar%20Sentinel%20Terraform%20y%20Notebooks.md).
- [AzureRM 5.10: AKS](https://registry.terraform.io/providers/hashicorp/azurerm/5.10.0/docs/resources/kubernetes_cluster).
- [AzureRM 5.10: DCR](https://registry.terraform.io/providers/hashicorp/azurerm/5.10.0/docs/resources/monitor_data_collection_rule).
- [AzureRM: onboarding de Sentinel](https://registry.terraform.io/providers/hashicorp/azurerm/5.10.0/docs/resources/sentinel_log_analytics_workspace_onboarding).
- [Requisitos de pools de sistema AKS](https://learn.microsoft.com/azure/aks/use-system-pools).
- [Habilitar monitoreo de AKS](https://learn.microsoft.com/azure/azure-monitor/containers/kubernetes-monitoring-enable).
- [Ejemplo oficial Terraform de Container Insights con MSI y DCR](https://github.com/microsoft/Docker-Provider/blob/ci_prod/scripts/onboarding/aks/onboarding-msi-terraform/main.tf).
- [Límite diario de Log Analytics](https://learn.microsoft.com/azure/azure-monitor/logs/daily-cap).
- [Calculadora de precios Azure](https://azure.microsoft.com/pricing/calculator/).
- [AzureRM: SSH public key](https://registry.terraform.io/providers/hashicorp/azurerm/5.10.0/docs/resources/ssh_public_key).
- [TLS: generación de clave privada y persistencia en estado](https://registry.terraform.io/providers/hashicorp/tls/4.4.2/docs/resources/private_key).
- [Random: contraseña generada y persistencia en estado](https://registry.terraform.io/providers/hashicorp/random/3.9.1/docs/resources/password).
- [Azure Key Vault: Private Link](https://learn.microsoft.com/azure/key-vault/general/private-link-service).
- [Categorías admitidas en diagnósticos AKS, incluida guard](https://learn.microsoft.com/azure/azure-monitor/reference/supported-logs/microsoft-containerservice-managedclusters-logs).
- [Auditoría de procesos y exposición de argumentos 4688](https://learn.microsoft.com/windows-server/identity/ad-ds/manage/component-updates/command-line-process-auditing).
- [auditpol: selección de subcategorías por GUID y permisos](https://learn.microsoft.com/windows-server/administration/windows-commands/auditpol-set).
