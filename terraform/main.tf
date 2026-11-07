locals {
  has_domain = var.domain_name != ""
}

module "network" {
  source = "./modules/network"
}
