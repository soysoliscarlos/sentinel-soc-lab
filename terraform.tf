terraform {
  required_version = ">= 1.7.5, < 2.0.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 5.10.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "= 3.10.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "= 3.9.1"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "= 4.4.2"
    }
  }
}
