locals {
  admin_username = "socadmin"
  tags = merge(var.tags, {
    Environment = "lab"
    ManagedBy   = "Terraform"
    Project     = "SOC-L2"
  })
  vm = {
    for name, config in {
      linux   = { admin_port = "22", enabled = var.create_linux_vm }
      windows = { admin_port = "3389", enabled = var.create_windows_vm }
    } : name => config if config.enabled
  }
  container_streams = [
    "Microsoft-ContainerLogV2",
    "Microsoft-KubeEvents",
    "Microsoft-KubePodInventory",
  ]
}
