# GitHub Actions -> AWS: organizația AWS interzice providerul OIDC (SCP), deci fiecare repo are un utilizator IAM
# dedicat, cu permisiuni înguste. Cheile NU sunt în Terraform: le creează scripts/github-keys.sh direct în
# secretele GitHub ale repo-ului. force_destroy le șterge la `terraform destroy`.

locals {
  account         = "712710404828"
  region          = "eu-north-1"
  service_arn     = "arn:aws:ecs:${local.region}:${local.account}:service/${var.cluster_name}/${var.service_name}"
  web_service_arn = "arn:aws:ecs:${local.region}:${local.account}:service/${var.cluster_name}/${coalesce(var.web_service_name, "none")}"
  web_task_roles  = compact([var.web_task_execution_role_arn, var.web_task_role_arn])

  # Statement-urile pe Sid (folosite și de teste).
  backend_stmt  = { for st in jsondecode(aws_iam_user_policy.backend.policy).Statement : st.Sid => st }
  frontend_stmt = { for st in flatten([for p in aws_iam_user_policy.frontend : jsondecode(p.policy).Statement]) : st.Sid => st }
}

# --- Backend: imagine în ECR + deploy pe serviciul ECS -----------------------

resource "aws_iam_user" "backend" {
  name          = "aradex-gha-backend"
  force_destroy = true
}

resource "aws_iam_user_policy" "backend" {
  name = "deploy-api"
  user = aws_iam_user.backend.name
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

# --- Frontend: imagine nginx în ECR + deploy pe serviciul web (doar cu domeniu) -------

resource "aws_iam_user" "frontend" {
  count         = var.enable_frontend ? 1 : 0
  name          = "aradex-gha-frontend"
  force_destroy = true
}

resource "aws_iam_user_policy" "frontend" {
  count = var.enable_frontend ? 1 : 0
  name  = "deploy-web"
  user  = aws_iam_user.frontend[0].name
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
        Resource = var.web_ecr_repository_arn
      },
      {
        Sid      = "EcsTaskDef"
        Effect   = "Allow"
        Action   = ["ecs:DescribeTaskDefinition", "ecs:RegisterTaskDefinition"]
        Resource = "*"
      },
      {
        Sid      = "EcsService"
        Effect   = "Allow"
        Action   = ["ecs:DescribeServices", "ecs:UpdateService"]
        Resource = local.web_service_arn
      },
      {
        Sid       = "PassTaskRoles"
        Effect    = "Allow"
        Action    = "iam:PassRole"
        Resource  = local.web_task_roles
        Condition = { StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" } }
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

# Configurația workflow-ului FE: repo-ul FE nu conține domeniul hardcodat.
resource "aws_ssm_parameter" "web" {
  for_each = var.enable_frontend ? { api_url = var.api_url } : {}
  name     = "/aradex/web/${each.key}"
  type     = "String"
  value    = each.value
}
