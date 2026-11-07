locals {
  has_domain = var.domain_name != ""
}

module "network" {
  source = "./modules/network"
}

module "data" {
  source              = "./modules/data"
  isolated_subnet_ids = module.network.isolated_subnet_ids
  db_sg_id            = module.network.db_sg_id
}
