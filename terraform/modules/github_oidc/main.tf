# GitHub Actions -> AWS fără chei: OIDC + câte un rol per repo, utilizabil doar de pe branch-ul de deploy.

locals {
  account     = "712710404828"
  region      = "eu-north-1"
  oidc_host   = "token.actions.githubusercontent.com"
  service_arn = "arn:aws:ecs:${local.region}:${local.account}:service/${var.cluster_name}/${var.service_name}"

  trust = { for repo in [var.backend_repo, var.frontend_repo] : repo => jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_host}:aud" = "sts.amazonaws.com"
          "${local.oidc_host}:sub" = "repo:${var.github_owner}/${repo}:ref:refs/heads/${var.branch}"
        }
      }
    }]
  }) }

  # Statement-urile pe Sid (folosite și de teste).
  backend_stmt  = { for st in jsondecode(aws_iam_role_policy.backend.policy).Statement : st.Sid => st }
  frontend_stmt = { for st in flatten([for p in aws_iam_role_policy.frontend : jsondecode(p.policy).Statement]) : st.Sid => st }
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://${local.oidc_host}"
  client_id_list = ["sts.amazonaws.com"]
}

# --- Backend: imagine în ECR + deploy pe serviciul ECS -----------------------

resource "aws_iam_role" "backend" {
  name               = "aradex-gha-backend"
  assume_role_policy = local.trust[var.backend_repo]
}

resource "aws_iam_role_policy" "backend" {
  name = "deploy-api"
  role = aws_iam_role.backend.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "EcrAuth"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "EcrPush"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability", "ecr:BatchGetImage", "ecr:CompleteLayerUpload",
          "ecr:GetDownloadUrlForLayer", "ecr:InitiateLayerUpload", "ecr:PutImage", "ecr:UploadLayerPart",
        ]
        Resource = var.ecr_repository_arn
      },
      {
        # Fără permisiuni la nivel de resursă pentru task definition-uri.
        Sid      = "EcsTaskDef"
        Effect   = "Allow"
        Action   = ["ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition"]
        Resource = "*"
      },
      {
        Sid      = "EcsService"
        Effect   = "Allow"
        Action   = ["ecs:DescribeServices", "ecs:UpdateService"]
        Resource = local.service_arn
      },
      {
        Sid       = "PassTaskRoles"
        Effect    = "Allow"
        Action    = "iam:PassRole"
        Resource  = [var.task_execution_role_arn, var.task_role_arn]
        Condition = { StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" } }
      },
    ]
  })
}

# --- Frontend: fișiere în S3 + invalidare CloudFront (doar cu domeniu) ---------

resource "aws_iam_role" "frontend" {
  count              = var.enable_frontend ? 1 : 0
  name               = "aradex-gha-frontend"
  assume_role_policy = local.trust[var.frontend_repo]
}

resource "aws_iam_role_policy" "frontend" {
  count = var.enable_frontend ? 1 : 0
  name  = "deploy-web"
  role  = aws_iam_role.frontend[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SiteList"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = var.bucket_arn
      },
      {
        Sid      = "SiteObjects"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${var.bucket_arn}/*"
      },
      {
        Sid      = "Invalidate"
        Effect   = "Allow"
        Action   = ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"]
        Resource = var.distribution_arn
      },
      {
        Sid      = "Config"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = "arn:aws:ssm:${local.region}:${local.account}:parameter/aradex/web/*"
      },
    ]
  })
}

# Configurația workflow-ului FE: repo-ul FE nu conține domeniu sau ID-uri hardcodate.
resource "aws_ssm_parameter" "web" {
  for_each = var.enable_frontend ? {
    bucket          = var.bucket_name
    distribution_id = var.distribution_id
    api_url         = var.api_url
  } : {}
  name  = "/aradex/web/${each.key}"
  type  = "String"
  value = each.value
}
