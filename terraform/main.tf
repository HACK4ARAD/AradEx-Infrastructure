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

module "edge" {
  source = "./modules/edge"
  count  = local.has_domain ? 1 : 0
  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
  domain_name  = var.domain_name
  alb_arn      = module.api.alb_arn
  alb_dns_name = module.api.alb_dns_name
}

module "github_deploy" {
  source                  = "./modules/github_deploy"
  github_owner            = var.github_owner
  backend_repo            = var.backend_repo
  frontend_repo           = var.frontend_repo
  branch                  = var.branch
  ecr_repository_arn      = module.api.ecr_repository_arn
  cluster_name            = module.api.cluster_name
  service_name            = module.api.service_name
  task_execution_role_arn = module.api.task_execution_role_arn
  task_role_arn           = module.api.task_role_arn
  enable_frontend         = local.has_domain
  bucket_name             = one(module.edge[*].bucket_name)
  bucket_arn              = one(module.edge[*].bucket_arn)
  distribution_id         = one(module.edge[*].distribution_id)
  distribution_arn        = one(module.edge[*].distribution_arn)
  api_url                 = local.has_domain ? "https://${var.domain_name}/api/v1" : null
}

module "monitoring" {
  source                  = "./modules/monitoring"
  alert_email             = var.alert_email
  api_desired_count       = var.api_desired_count
  alb_arn_suffix          = module.api.alb_arn_suffix
  target_group_arn_suffix = module.api.target_group_arn_suffix
  cluster_name            = module.api.cluster_name
  service_name            = module.api.service_name
}
