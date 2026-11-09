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
  source                   = "./modules/api"
  vpc_id                   = module.network.vpc_id
  public_subnet_ids        = module.network.public_subnet_ids
  isolated_subnet_ids      = module.network.isolated_subnet_ids
  alb_sg_id                = module.network.alb_sg_id
  task_sg_id               = module.network.task_sg_id
  db_endpoint              = module.data.db_endpoint
  db_secret_arn            = module.data.db_secret_arn
  jwt_secret_arn           = module.data.jwt_secret_arn
  anthropic_secret_arn     = module.data.anthropic_secret_arn
  google_places_secret_arn = module.data.google_places_secret_arn
  stripe_secret_arn        = module.data.stripe_secret_arn
  anthropic_model          = var.anthropic_model
  domain_name              = var.domain_name
  desired_count            = var.api_desired_count
  enable_https             = local.has_domain
  certificate_arn          = one(module.edge[*].certificate_arn)
  enable_email             = local.has_domain
  ses_identity_arn         = one(module.edge[*].ses_identity_arn)
}

module "web" {
  source            = "./modules/web"
  count             = local.has_domain ? 1 : 0
  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
  web_sg_id         = module.network.web_sg_id
  cluster_arn       = module.api.cluster_arn
  listener_arn      = module.api.https_listener_arn
  target_group_arn  = module.api.web_target_group_arn
  desired_count     = var.web_desired_count
}

module "edge" {
  source = "./modules/edge"
  count  = local.has_domain ? 1 : 0
  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
  domain_name  = var.domain_name
  alb_dns_name = module.api.alb_dns_name
  alb_zone_id  = module.api.alb_zone_id
}

module "github_deploy" {
  source                      = "./modules/github_deploy"
  github_owner                = var.github_owner
  backend_repo                = var.backend_repo
  frontend_repo               = var.frontend_repo
  branch                      = var.branch
  ecr_repository_arn          = module.api.ecr_repository_arn
  cluster_name                = module.api.cluster_name
  service_name                = module.api.service_name
  task_execution_role_arn     = module.api.task_execution_role_arn
  task_role_arn               = module.api.task_role_arn
  enable_frontend             = local.has_domain
  web_ecr_repository_arn      = one(module.web[*].ecr_repository_arn)
  web_service_name            = one(module.web[*].service_name)
  web_task_execution_role_arn = one(module.web[*].task_execution_role_arn)
  web_task_role_arn           = null
  api_url                     = local.has_domain ? "https://${var.domain_name}/api/v1" : null
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
