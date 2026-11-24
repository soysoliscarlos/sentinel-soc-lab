variable "ad_domain_name" {
  description = "DNS FQDN of the new Active Directory (AD DS) forest for Windows Server."
  type        = string
  default     = "lab.example.test"
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9][-a-zA-Z0-9.]+[a-zA-Z0-9]$", var.ad_domain_name)) && length(var.ad_domain_name) >= 3 && length(var.ad_domain_name) <= 255
    error_message = "Provide a valid DNS FQDN for the Active Directory forest."
  }
}

variable "ad_domain_netbios" {
  description = "NetBIOS name of the Active Directory domain (up to 15 uppercase alphanumeric characters)."
  type        = string
  default     = "LAB"
  nullable    = false

  validation {
    condition     = can(regex("^[A-Z0-9-]{1,15}$", var.ad_domain_netbios))
    error_message = "NetBIOS name must be 1 to 15 uppercase alphanumeric characters or hyphens."
  }
}

variable "admin_source_cidr" {
  description = "Approved public IPv4 CIDR for SSH, RDP, AKS API, and Key Vault (/24 to /32). Do not use a private CIDR."
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
    error_message = "Provide a public IPv4 CIDR between /24 and /32. Private, loopback, link-local, and CGNAT ranges are not allowed."
  }
}

variable "aks_load_balancer_sku" {
  description = "AKS Load Balancer SKU; this lab requires standard."
  type        = string
  default     = "standard"

  validation {
    condition     = var.aks_load_balancer_sku == "standard"
    error_message = "AKS requires the standard load balancer SKU in this lab."
  }
}

variable "aks_node_count" {
  description = "Fixed number of AKS nodes; minimum of two in the system node pool."
  type        = number
  default     = 2

  validation {
    condition     = var.aks_node_count >= 2 && var.aks_node_count <= 3 && floor(var.aks_node_count) == var.aks_node_count
    error_message = "This lab supports two or three system nodes."
  }
}

variable "aks_node_vm_size" {
  description = "AKS system node pool VM SKU: minimum 4 vCPU / 4 GB, excluding B-series. Check quota and regional availability."
  type        = string
  default     = "Standard_D4s_v6"
}

variable "aks_os_sku" {
  description = "AKS node OS SKU; Ubuntu is the validated profile."
  type        = string
  default     = "Ubuntu"

  validation {
    condition     = var.aks_os_sku == "Ubuntu"
    error_message = "This lab profile requires Ubuntu on AKS."
  }
}

variable "aks_sku_tier" {
  description = "AKS cluster management tier; excludes node compute costs."
  type        = string
  default     = "Free"

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.aks_sku_tier)
    error_message = "AKS SKU tier must be Free, Standard, or Premium."
  }
}

variable "app_service_sku" {
  description = "Linux App Service SKU supporting always-on and diagnostics; B1 is the lab baseline."
  type        = string
  default     = "B1"

  validation {
    condition     = contains(["B1", "B2", "B3", "S1", "S2", "S3", "P1v3", "P2v3", "P3v3"], var.app_service_sku)
    error_message = "Use a Basic, Standard, or Premium v3 SKU compatible with the lab."
  }
}

variable "create_aks" {
  description = "Creates AKS and its dedicated identity, networking, and monitoring resources."
  type        = bool
  default     = true
  nullable    = false
}

variable "create_app_service" {
  description = "Creates Linux App Service, its service plan, and its diagnostic settings."
  type        = bool
  default     = true
  nullable    = false
}

variable "create_linux_vm" {
  description = "Creates the Linux VM and its dedicated networking, credential, and monitoring resources."
  type        = bool
  default     = true
  nullable    = false
}

variable "create_windows_vm" {
  description = "Creates the Windows VM and its dedicated networking, credential, and monitoring resources."
  type        = bool
  default     = true
  nullable    = false
}

variable "key_vault_name_suffix" {
  description = "Key Vault name suffix (<name_prefix>-<suffix>). Changing it replaces the vault; useful when a prior vault name remains reserved in soft delete."
  type        = string
  default     = "kv01"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z0-9]{2,4}$", var.key_vault_name_suffix))
    error_message = "Use 2 to 4 lowercase letters or digits so the full vault name does not exceed 24 characters."
  }
}

variable "key_vault_sku" {
  description = "Key Vault SKU; premium adds HSM-backed key support."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "Key Vault SKU must be standard or premium."
  }
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version available in the region; null lets Azure pick a supported default version."
  type        = string
  default     = null
}

variable "linux_image_sku" {
  description = "Linux image SKU within Canonical/0001-com-ubuntu-server-jammy; verify compatibility before changing."
  type        = string
  default     = "22_04-lts-gen2"
}

variable "linux_os_disk_sku" {
  description = "Storage account type for the Linux OS disk."
  type        = string
  default     = "Standard_LRS"

  validation {
    condition     = contains(["Standard_LRS", "StandardSSD_LRS", "Premium_LRS", "StandardSSD_ZRS", "Premium_ZRS"], var.linux_os_disk_sku)
    error_message = "Use a supported OS disk type: Standard_LRS, StandardSSD_LRS, Premium_LRS, StandardSSD_ZRS, or Premium_ZRS."
  }
}

variable "linux_vm_size" {
  description = "Ubuntu VM SKU; verify subscription quota and regional availability."
  type        = string
  default     = "Standard_D2s_v6"
}

variable "location" {
  description = "Azure region shared across all lab resources."
  type        = string
  default     = "eastus2"
}

variable "log_daily_quota_gb" {
  description = "Log Analytics daily ingestion cap in GB. Not a hard billing ceiling and may halt telemetry once reached."
  type        = number
  default     = 1

  validation {
    condition     = var.log_daily_quota_gb >= 0.1
    error_message = "Daily quota must be at least 0.1 GB."
  }
}

variable "log_retention_days" {
  description = "Log Analytics workspace retention in days; verify Sentinel pricing terms."
  type        = number
  default     = 30

  validation {
    condition     = var.log_retention_days >= 30 && var.log_retention_days <= 730 && floor(var.log_retention_days) == var.log_retention_days
    error_message = "Retention must be an integer between 30 and 730 days."
  }
}

variable "log_workspace_sku" {
  description = "Log Analytics workspace SKU integrated with Sentinel; this lab uses pay-as-you-go ingestion."
  type        = string
  default     = "PerGB2018"

  validation {
    condition     = var.log_workspace_sku == "PerGB2018"
    error_message = "This lab requires PerGB2018; commitment tiers require billing and configuration review."
  }
}

variable "name_prefix" {
  description = "Globally unique prefix for lab resources and the public App Service hostname."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,17}[a-z0-9]$", var.name_prefix)) && !strcontains(var.name_prefix, "--")
    error_message = "Use 4 to 19 characters: lowercase letters, digits, and non-consecutive hyphens; start with a letter and end with a letter or digit."
  }
}

variable "public_ip_sku" {
  description = "SKU for VM public IP addresses; Standard is required for this profile."
  type        = string
  default     = "Standard"

  validation {
    condition     = var.public_ip_sku == "Standard"
    error_message = "Lab public IP addresses must use the Standard SKU."
  }
}

variable "subscription_id" {
  description = "Target Azure subscription ID. No implicit subscription selection is used."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "Provide a valid subscription UUID."
  }
}

variable "tags" {
  description = "Additional resource tags; Environment, ManagedBy, and Project remain fixed for the lab."
  type        = map(string)
  default     = {}
}

variable "windows_image_sku" {
  description = "Windows image SKU within MicrosoftWindowsServer/WindowsServer; verify compatibility before changing."
  type        = string
  default     = "2022-datacenter-azure-edition"
}

variable "windows_os_disk_sku" {
  description = "Storage account type for the Windows OS disk."
  type        = string
  default     = "Standard_LRS"

  validation {
    condition     = contains(["Standard_LRS", "StandardSSD_LRS", "Premium_LRS", "StandardSSD_ZRS", "Premium_ZRS"], var.windows_os_disk_sku)
    error_message = "Use a supported OS disk type: Standard_LRS, StandardSSD_LRS, Premium_LRS, StandardSSD_ZRS, or Premium_ZRS."
  }
}

variable "windows_vm_size" {
  description = "Windows Server VM SKU."
  type        = string
  default     = "Standard_D2s_v6"
}
