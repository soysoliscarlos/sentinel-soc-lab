variable "ad_domain_name" {
  description = "Nombre DNS FQDN del nuevo bosque de Active Directory (AD DS) para Windows Server."
  type        = string
  default     = "lab.example.test"
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9][-a-zA-Z0-9.]+[a-zA-Z0-9]$", var.ad_domain_name)) && length(var.ad_domain_name) >= 3 && length(var.ad_domain_name) <= 255
    error_message = "Indica un nombre DNS FQDN valido para el bosque Active Directory."
  }
}

variable "ad_domain_netbios" {
  description = "Nombre NetBIOS del dominio de Active Directory (maximo 15 caracteres alfanumericos en mayusculas)."
  type        = string
  default     = "LAB"
  nullable    = false

  validation {
    condition     = can(regex("^[A-Z0-9-]{1,15}$", var.ad_domain_netbios))
    error_message = "El nombre NetBIOS debe tener entre 1 y 15 caracteres alfanumericos o guion en mayusculas."
  }
}

variable "admin_source_cidr" {
  description = "CIDR IPv4 publico autorizado para SSH, RDP, API de AKS y Key Vault; /24 a /32. No usar un CIDR privado."
  type        = string
  nullable    = false

  validation {
    condition = try(
      can(cidrnetmask(var.admin_source_cidr)) &&
      tonumber(split("/", var.admin_source_cidr)[1]) >= 24 &&
      tonumber(split("/", var.admin_source_cidr)[1]) <= 32 &&
      tonumber(split(".", cidrhost(var.admin_source_cidr, 0))[0]) >= 1 &&
      tonumber(split(".", cidrhost(var.admin_source_cidr, 0))[0]) < 224 &&
      !can(regex("^(10\\.|127\\.|169\\.254\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.|192\\.168\\.|100\\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\\.)", cidrhost(var.admin_source_cidr, 0))),
      false
    )
    error_message = "Indica un CIDR IPv4 publico /24 a /32. No se permiten rangos privados, loopback, link-local ni CGNAT."
  }
}

variable "aks_load_balancer_sku" {
  description = "SKU del balanceador AKS; el laboratorio requiere standard."
  type        = string
  default     = "standard"

  validation {
    condition     = var.aks_load_balancer_sku == "standard"
    error_message = "AKS requiere el balanceador standard en este laboratorio."
  }
}

variable "aks_node_count" {
  description = "Numero fijo de nodos AKS; minimo dos en el pool de sistema."
  type        = number
  default     = 2

  validation {
    condition     = var.aks_node_count >= 2 && var.aks_node_count <= 3 && floor(var.aks_node_count) == var.aks_node_count
    error_message = "El laboratorio admite dos o tres nodos de sistema."
  }
}

variable "aks_node_vm_size" {
  description = "SKU del pool de sistema AKS: minimo 4 vCPU/4 GB, no serie B. Comprobar cuota y disponibilidad."
  type        = string
  default     = "Standard_D4s_v6"
}

variable "aks_os_sku" {
  description = "SKU del sistema operativo de los nodos AKS; Ubuntu es el perfil validado."
  type        = string
  default     = "Ubuntu"

  validation {
    condition     = var.aks_os_sku == "Ubuntu"
    error_message = "El perfil del laboratorio requiere Ubuntu en AKS."
  }
}

variable "aks_sku_tier" {
  description = "Nivel de administracion AKS; no incluye el costo de los nodos."
  type        = string
  default     = "Free"

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.aks_sku_tier)
    error_message = "El nivel AKS debe ser Free, Standard o Premium."
  }
}

variable "app_service_sku" {
  description = "SKU de App Service Linux con always-on y diagnosticos; B1 como base del laboratorio."
  type        = string
  default     = "B1"

  validation {
    condition     = contains(["B1", "B2", "B3", "S1", "S2", "S3", "P1v3", "P2v3", "P3v3"], var.app_service_sku)
    error_message = "Usa un SKU Basic, Standard o Premium v3 compatible con el laboratorio."
  }
}

variable "create_aks" {
  description = "Crea AKS y sus recursos exclusivos de identidad, red y monitoreo."
  type        = bool
  default     = true
  nullable    = false
}

variable "create_app_service" {
  description = "Crea App Service Linux, su plan y sus diagnosticos."
  type        = bool
  default     = true
  nullable    = false
}

variable "create_linux_vm" {
  description = "Crea la VM Linux y sus recursos exclusivos de red, credenciales y monitoreo."
  type        = bool
  default     = true
  nullable    = false
}

variable "create_windows_vm" {
  description = "Crea la VM Windows y sus recursos exclusivos de red, credenciales y monitoreo."
  type        = bool
  default     = true
  nullable    = false
}

variable "key_vault_name_suffix" {
  description = "Sufijo del nombre del Key Vault (<name_prefix>-<sufijo>). Cambiarlo reemplaza el vault; util cuando un nombre anterior sigue reservado en soft delete."
  type        = string
  default     = "kv01"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]{2,4}$", var.key_vault_name_suffix))
    error_message = "Usa de 2 a 4 minusculas o numeros para que el nombre del vault no supere 24 caracteres."
  }
}

variable "key_vault_sku" {
  description = "SKU de Key Vault; premium agrega soporte HSM para claves."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "El SKU de Key Vault debe ser standard o premium."
  }
}

variable "kubernetes_version" {
  description = "Version AKS disponible en la region; null permite que Azure seleccione una version soportada."
  type        = string
  default     = null
}

variable "linux_image_sku" {
  description = "SKU de imagen Linux dentro de Canonical/0001-com-ubuntu-server-jammy; validar compatibilidad antes de cambiarlo."
  type        = string
  default     = "22_04-lts-gen2"
}

variable "linux_os_disk_sku" {
  description = "Tipo de almacenamiento del disco de sistema Linux."
  type        = string
  default     = "Standard_LRS"

  validation {
    condition     = contains(["Standard_LRS", "StandardSSD_LRS", "Premium_LRS", "StandardSSD_ZRS", "Premium_ZRS"], var.linux_os_disk_sku)
    error_message = "Usa un tipo de disco de sistema compatible: Standard_LRS, StandardSSD_LRS, Premium_LRS, StandardSSD_ZRS o Premium_ZRS."
  }
}

variable "linux_vm_size" {
  description = "SKU de la VM Ubuntu; validar cuota y disponibilidad en la suscripcion."
  type        = string
  default     = "Standard_D2s_v6"
}

variable "location" {
  description = "Region compartida por los recursos del laboratorio."
  type        = string
  default     = "eastus2"
}

variable "log_daily_quota_gb" {
  description = "Umbral diario de Log Analytics. No es un tope de gasto y puede interrumpir parte de la telemetria."
  type        = number
  default     = 1

  validation {
    condition     = var.log_daily_quota_gb >= 0.1
    error_message = "La cuota debe ser al menos 0.1 GB diarios."
  }
}

variable "log_retention_days" {
  description = "Retencion del workspace en dias; validar condiciones y costos de Sentinel."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730 && floor(var.log_retention_days) == var.log_retention_days
    error_message = "La retencion debe ser un entero entre 30 y 730 dias."
  }
}

variable "log_workspace_sku" {
  description = "SKU del workspace integrado con Sentinel; este laboratorio usa pago por ingesta."
  type        = string
  default     = "PerGB2018"

  validation {
    condition     = var.log_workspace_sku == "PerGB2018"
    error_message = "El laboratorio requiere PerGB2018; otros niveles necesitan revisar facturacion y configuracion."
  }
}

variable "name_prefix" {
  description = "Prefijo globalmente unico para el laboratorio y el nombre publico de App Service."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,17}[a-z0-9]$", var.name_prefix)) && !strcontains(var.name_prefix, "--")
    error_message = "Usa de 4 a 19 caracteres: minusculas, numeros y guiones no consecutivos; empieza con letra y termina con letra o numero."
  }
}

variable "public_ip_sku" {
  description = "SKU de las IP publicas de las VM; Standard es obligatorio para este perfil."
  type        = string
  default     = "Standard"

  validation {
    condition     = var.public_ip_sku == "Standard"
    error_message = "Las IP publicas del laboratorio deben usar Standard."
  }
}

variable "subscription_id" {
  description = "ID de la suscripcion destino. El codigo no selecciona una suscripcion implicitamente."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "Indica un UUID de suscripcion valido."
  }
}

variable "tags" {
  description = "Etiquetas adicionales; Environment y ManagedBy permanecen fijadas para el laboratorio."
  type        = map(string)
  default     = {}
}

variable "windows_image_sku" {
  description = "SKU de imagen Windows dentro de MicrosoftWindowsServer/WindowsServer; validar compatibilidad antes de cambiarlo."
  type        = string
  default     = "2022-datacenter-azure-edition"
}

variable "windows_os_disk_sku" {
  description = "Tipo de almacenamiento del disco de sistema Windows."
  type        = string
  default     = "Standard_LRS"

  validation {
    condition     = contains(["Standard_LRS", "StandardSSD_LRS", "Premium_LRS", "StandardSSD_ZRS", "Premium_ZRS"], var.windows_os_disk_sku)
    error_message = "Usa un tipo de disco de sistema compatible: Standard_LRS, StandardSSD_LRS, Premium_LRS, StandardSSD_ZRS o Premium_ZRS."
  }
}

variable "windows_vm_size" {
  description = "SKU de la VM Windows Server."
  type        = string
  default     = "Standard_D2s_v6"
}
