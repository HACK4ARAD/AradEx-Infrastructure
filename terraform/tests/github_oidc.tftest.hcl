mock_provider "aws" {
  mock_resource "aws_iam_openid_connect_provider" {
    defaults = { arn = "arn:aws:iam::712710404828:oidc-provider/token.actions.githubusercontent.com" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::712710404828:role/mock" }
  }
}

variables {
  github_owner            = "HACK4ARAD"
  backend_repo            = "AradEx-Backend"
  frontend_repo           = "AradEx-Frontend"
  branch                  = "main"
  ecr_repository_arn      = "arn:aws:ecr:eu-north-1:712710404828:repository/aradex-api"
  cluster_name            = "aradex"
  service_name            = "aradex-api"
  task_execution_role_arn = "arn:aws:iam::712710404828:role/aradex-api-execution"
  task_role_arn           = "arn:aws:iam::712710404828:role/aradex-api-task"
  enable_frontend         = true
  bucket_name             = "aradex-site-mock"
  bucket_arn              = "arn:aws:s3:::aradex-site-mock"
  distribution_id         = "EMOCK123"
  distribution_arn        = "arn:aws:cloudfront::712710404828:distribution/EMOCK123"
  api_url                 = "https://aradex.example/api/v1"
}

run "github_oidc" {
  command = apply
  module {
    source = "./modules/github_oidc"
  }

  assert {
    condition     = aws_iam_openid_connect_provider.github.url == "https://token.actions.githubusercontent.com" && tolist(aws_iam_openid_connect_provider.github.client_id_list) == tolist(["sts.amazonaws.com"])
    error_message = "github oidc provider"
  }
  # Doar repo-ul Backend, doar main (StringEquals, nu wildcard).
  assert {
    condition = (
      aws_iam_role.backend.name == "aradex-gha-backend" &&
      jsondecode(aws_iam_role.backend.assume_role_policy).Statement[0].Action == "sts:AssumeRoleWithWebIdentity" &&
      jsondecode(aws_iam_role.backend.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:aud"] == "sts.amazonaws.com" &&
      jsondecode(aws_iam_role.backend.assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:HACK4ARAD/AradEx-Backend:ref:refs/heads/main" &&
      !can(jsondecode(aws_iam_role.backend.assume_role_policy).Statement[0].Condition.StringLike)
    )
    error_message = "backend trust: only HACK4ARAD/AradEx-Backend on main"
  }
  assert {
    condition = (
      local.backend_stmt["EcrPush"].Resource == var.ecr_repository_arn &&
      local.backend_stmt["EcrAuth"].Action == "ecr:GetAuthorizationToken" &&
      local.backend_stmt["EcsService"].Resource == "arn:aws:ecs:eu-north-1:712710404828:service/aradex/aradex-api" &&
      toset(local.backend_stmt["EcsService"].Action) == toset(["ecs:DescribeServices", "ecs:UpdateService"]) &&
      toset(local.backend_stmt["EcsTaskDef"].Action) == toset(["ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition"]) &&
      toset(local.backend_stmt["PassTaskRoles"].Resource) == toset([var.task_execution_role_arn, var.task_role_arn]) &&
      local.backend_stmt["PassTaskRoles"].Condition.StringEquals["iam:PassedToService"] == "ecs-tasks.amazonaws.com"
    )
    error_message = "backend permissions"
  }
  assert {
    condition = (
      aws_iam_role.frontend[0].name == "aradex-gha-frontend" &&
      jsondecode(aws_iam_role.frontend[0].assume_role_policy).Statement[0].Condition.StringEquals["token.actions.githubusercontent.com:sub"] == "repo:HACK4ARAD/AradEx-Frontend:ref:refs/heads/main"
    )
    error_message = "frontend trust: only HACK4ARAD/AradEx-Frontend on main"
  }
  assert {
    condition = (
      local.frontend_stmt["SiteList"].Resource == var.bucket_arn &&
      local.frontend_stmt["SiteObjects"].Resource == "${var.bucket_arn}/*" &&
      local.frontend_stmt["Invalidate"].Resource == var.distribution_arn &&
      toset(local.frontend_stmt["Invalidate"].Action) == toset(["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"]) &&
      local.frontend_stmt["Config"].Resource == "arn:aws:ssm:eu-north-1:712710404828:parameter/aradex/web/*"
    )
    error_message = "frontend permissions"
  }
  assert {
    condition = (
      aws_ssm_parameter.web["bucket"].name == "/aradex/web/bucket" && aws_ssm_parameter.web["bucket"].value == "aradex-site-mock" &&
      aws_ssm_parameter.web["distribution_id"].value == "EMOCK123" &&
      aws_ssm_parameter.web["api_url"].value == "https://aradex.example/api/v1"
    )
    error_message = "ssm parameters for the frontend workflow"
  }
}

run "no_frontend_without_domain" {
  command = apply
  module {
    source = "./modules/github_oidc"
  }
  variables {
    enable_frontend  = false
    bucket_name      = null
    bucket_arn       = null
    distribution_id  = null
    distribution_arn = null
    api_url          = null
  }
  assert {
    condition     = length(aws_iam_role.frontend) == 0 && length(aws_ssm_parameter.web) == 0 && aws_iam_role.backend.name == "aradex-gha-backend"
    error_message = "only the backend role without a domain"
  }
}
