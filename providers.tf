provider "azuread" {}

provider "azurerm" {
  subscription_id                 = var.subscription_id
  resource_provider_registrations = "none"

  features {
    key_vault {
      purge_soft_delete_on_destroy               = true
      purge_soft_deleted_certificates_on_destroy = true
      purge_soft_deleted_keys_on_destroy         = true
      purge_soft_deleted_secrets_on_destroy      = true
      recover_soft_deleted_key_vaults            = false
      recover_soft_deleted_certificates          = false
      recover_soft_deleted_keys                  = false
      recover_soft_deleted_secrets               = false
    }

    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }

    virtual_machine {
      delete_os_disk_on_deletion = true
    }

    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}
