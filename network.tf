resource "azurerm_virtual_network" "lab" {
  name                = "${var.name_prefix}-vnet"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = ["10.20.0.0/16"]
  tags                = local.tags
}

resource "azurerm_subnet" "vm" {
  count = length(local.vm) > 0 ? 1 : 0

  name                 = "snet-vm"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = ["10.20.1.0/24"]
}

resource "azurerm_subnet" "aks" {
  count = var.create_aks ? 1 : 0

  name                 = "snet-aks"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = ["10.20.2.0/24"]
}

resource "azurerm_public_ip" "vm" {
  for_each = local.vm

  name                = "${var.name_prefix}-${each.key}-pip"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = var.public_ip_sku
  tags                = local.tags
}

resource "azurerm_network_security_group" "vm" {
  for_each = local.vm

  name                = "${var.name_prefix}-${each.key}-nsg"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  security_rule {
    name                       = "AllowAdminFromApprovedCIDR"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = each.value.admin_port
    source_address_prefix      = var.admin_source_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "DenyOtherInbound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  dynamic "security_rule" {
    for_each = var.enable_ansible ? [true] : []
    content {
      name                       = "AllowLabHTTPFromApprovedCIDR"
      priority                   = 110
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "80"
      source_address_prefix      = var.admin_source_cidr
      destination_address_prefix = "*"
    }
  }

  dynamic "security_rule" {
    for_each = var.enable_ansible && each.key == "windows" ? [true] : []
    content {
      name                       = "AllowAnsibleSSHFromApprovedCIDR"
      priority                   = 120
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "22"
      source_address_prefix      = var.admin_source_cidr
      destination_address_prefix = "*"
    }
  }
}

resource "azurerm_network_interface" "vm" {
  for_each = local.vm

  name                = "${var.name_prefix}-${each.key}-nic"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  ip_configuration {
    name                          = "primary"
    subnet_id                     = azurerm_subnet.vm[0].id
    private_ip_address_allocation = var.enable_ansible && each.key == "windows" ? "Static" : "Dynamic"
    private_ip_address            = var.enable_ansible && each.key == "windows" ? "10.20.1.10" : null
    public_ip_address_id          = azurerm_public_ip.vm[each.key].id
  }
}

resource "azurerm_network_interface_security_group_association" "vm" {
  for_each = local.vm

  network_interface_id      = azurerm_network_interface.vm[each.key].id
  network_security_group_id = azurerm_network_security_group.vm[each.key].id
}
