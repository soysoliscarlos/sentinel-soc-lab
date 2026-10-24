variable "enable_sentinel_notebooks" {
  description = "Crea un workspace de Azure Machine Learning (con su storage, Key Vault y Application Insights) y una compute instance para ejecutar los notebooks de Sentinel. La compute instance factura por hora mientras esta encendida."
  type        = bool
  default     = false
  nullable    = false
}

variable "sentinel_notebook_compute_size" {
  description = "Tamano de la compute instance de Azure ML que ejecuta los notebooks; validar cuota y costo antes de cambiarlo."
  type        = string
  default     = "Standard_DS2_v2"
  nullable    = false
}

resource "azurerm_storage_account" "ml" {
  count = var.enable_sentinel_notebooks ? 1 : 0

  name                            = "${replace(var.name_prefix, "-", "")}mlsa"
  resource_group_name             = azurerm_resource_group.lab.name
  location                        = azurerm_resource_group.lab.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  tags                            = local.tags
}

resource "azurerm_key_vault" "ml" {
  count = var.enable_sentinel_notebooks ? 1 : 0

  name                          = "${var.name_prefix}-ml-kv"
  resource_group_name           = azurerm_resource_group.lab.name
  location                      = azurerm_resource_group.lab.location
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  public_network_access_enabled = true
  soft_delete_retention_days    = 7
  # Debe permanecer deshabilitado para que terraform destroy pueda purgar el vault del laboratorio.
  purge_protection_enabled = false
  tags                     = local.tags
}

resource "azurerm_application_insights" "ml" {
  count = var.enable_sentinel_notebooks ? 1 : 0

  name                = "${var.name_prefix}-ml-ai"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.soc.id
  tags                = local.tags
}

resource "azurerm_machine_learning_workspace" "soc" {
  count = var.enable_sentinel_notebooks ? 1 : 0

  name                          = "${var.name_prefix}-mlw"
  resource_group_name           = azurerm_resource_group.lab.name
  location                      = azurerm_resource_group.lab.location
  application_insights_id       = azurerm_application_insights.ml[0].id
  key_vault_id                  = azurerm_key_vault.ml[0].id
  storage_account_id            = azurerm_storage_account.ml[0].id
  public_network_access_enabled = true
  tags                          = local.tags

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_machine_learning_compute_instance" "soc" {
  count = var.enable_sentinel_notebooks ? 1 : 0

  name                          = "${var.name_prefix}-ci"
  machine_learning_workspace_id = azurerm_machine_learning_workspace.soc[0].id
  virtual_machine_size          = var.sentinel_notebook_compute_size
  tags                          = local.tags

  identity {
    type = "SystemAssigned"
  }

  assign_to_user {
    object_id = data.azurerm_client_config.current.object_id
    tenant_id = data.azurerm_client_config.current.tenant_id
  }
}

# Permite que los notebooks (via DefaultAzureCredential con la identidad de la compute instance)
# consulten el workspace de Log Analytics del laboratorio.
resource "azurerm_role_assignment" "notebook_log_reader" {
  count = var.enable_sentinel_notebooks ? 1 : 0

  scope                = azurerm_log_analytics_workspace.soc.id
  role_definition_name = "Log Analytics Reader"
  principal_id         = azurerm_machine_learning_compute_instance.soc[0].identity[0].principal_id
}

variable "sentinel_notebooks_trigger" {
  description = "Disparador para resincronizar los notebooks con Azure Machine Learning en un apply posterior."
  type        = string
  default     = "v2"
  nullable    = false
}

# Sincroniza y sube los notebooks de notebooks/ al filestore de Azure Machine Learning
resource "terraform_data" "upload_notebooks" {
  count = var.enable_sentinel_notebooks ? 1 : 0

  triggers_replace = [
    azurerm_machine_learning_workspace.soc[0].id,
    var.sentinel_notebooks_trigger
  ]

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command"]
    command     = <<-POWERSHELL
      $shareName = "azureml-filestore-$env:AML_WORKSPACE_ID"
      $notebooks = Get-ChildItem -Path "$env:NOTEBOOKS_DIR" -Filter "*.ipynb"
      $key = az storage account keys list -g $env:RESOURCE_GROUP -n $env:STORAGE_ACCOUNT_NAME --query "[0].value" -o tsv
      foreach ($nb in $notebooks) {
        Write-Host "Subiendo cuaderno $($nb.Name) a Azure ML ($shareName)..."
        az storage file upload --share-name $shareName --source $nb.FullName --account-name $env:STORAGE_ACCOUNT_NAME --account-key $key --only-show-errors
      }
      $codeShares = az storage share list --account-name $env:STORAGE_ACCOUNT_NAME --account-key $key --query "[?starts_with(name, 'code-')].name" -o tsv
      foreach ($cs in $codeShares) {
        $users = az storage file list --share-name $cs --path "Users" --account-name $env:STORAGE_ACCOUNT_NAME --account-key $key --query "[?type=='dir'].name" -o tsv 2>$null
        foreach ($u in $users) {
          foreach ($nb in $notebooks) {
            Write-Host "Sincronizando $($nb.Name) a Users/$u en $cs..."
            az storage file upload --share-name $cs --source $nb.FullName --path "Users/$u/$($nb.Name)" --account-name $env:STORAGE_ACCOUNT_NAME --account-key $key --only-show-errors
          }
        }
      }
      Write-Host "Cuadernos sincronizados exitosamente con Azure Machine Learning."
    POWERSHELL

    environment = {
      AML_WORKSPACE_ID     = azurerm_machine_learning_workspace.soc[0].workspace_id
      STORAGE_ACCOUNT_NAME = azurerm_storage_account.ml[0].name
      RESOURCE_GROUP       = azurerm_resource_group.lab.name
      NOTEBOOKS_DIR        = abspath("${path.module}/notebooks")
    }
  }

  depends_on = [
    azurerm_machine_learning_workspace.soc,
    azurerm_machine_learning_compute_instance.soc,
    azurerm_role_assignment.notebook_log_reader
  ]
}

