locals {
  network = module.ip_plan.networks["shared/${var.region}"]
  tables  = ["restricted", "standard", "shared"]

  # The resolver endpoints need the hub layout's dns tier.
  dns_tier = contains(keys(local.network.subnets), "dns")
}
