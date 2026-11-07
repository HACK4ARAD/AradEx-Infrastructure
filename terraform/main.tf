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

module "api" {
  source              = "./modules/api"
  vpc_id              = module.network.vpc_id
  public_subnet_ids   = module.network.public_subnet_ids
  isolated_subnet_ids = module.network.isolated_subnet_ids
  alb_sg_id           = module.network.alb_sg_id
  task_sg_id          = module.network.task_sg_id
  db_endpoint         = module.data.db_endpoint
  db_secret_arn       = module.data.db_secret_arn
  jwt_secret_arn      = module.data.jwt_secret_arn
  openai_secret_arn   = module.data.openai_secret_arn
  domain_name         = var.domain_name
  desired_count       = var.api_desired_count
}
