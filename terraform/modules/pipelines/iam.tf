locals {
  account = "712710404828"
  region  = "eu-north-1"

  trust = { for svc in ["codebuild", "codepipeline"] : svc => jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "${svc}.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = local.account } }
    }]
  }) }
}

# --- CodeBuild: loguri, artefacte, ECR push, S3 site, invalidare CloudFront, rapoarte de teste ---
resource "aws_iam_role" "codebuild" {
  name               = "aradex-codebuild"
  assume_role_policy = local.trust["codebuild"]
}

resource "aws_iam_role_policy" "codebuild" {
  name = "aradex-codebuild"
  role = aws_iam_role.codebuild.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["${aws_cloudwatch_log_group.codebuild.arn}:*"]
      },
      {
        Sid      = "Artifacts"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"]
        Resource = ["${aws_s3_bucket.artifacts.arn}/*"]
      },
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
        Action   = "cloudfront:CreateInvalidation"
        Resource = var.distribution_arn
      },
      {
        Sid    = "TestReports"
        Effect = "Allow"
        Action = [
          "codebuild:CreateReportGroup", "codebuild:CreateReport", "codebuild:UpdateReport",
          "codebuild:BatchPutTestCases", "codebuild:BatchPutCodeCoverages",
        ]
        Resource = "arn:aws:codebuild:${local.region}:${local.account}:report-group/aradex-*"
      },
    ]
  })
}

# --- CodePipeline: artefacte, conexiunea GitHub, pornire CodeBuild, deploy ECS ---
resource "aws_iam_role" "codepipeline" {
  name               = "aradex-codepipeline"
  assume_role_policy = local.trust["codepipeline"]
}

resource "aws_iam_role_policy" "codepipeline" {
  name = "aradex-codepipeline"
  role = aws_iam_role.codepipeline.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "Artifacts"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:GetBucketVersioning", "s3:PutObject", "s3:PutObjectAcl"]
        Resource = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
      },
      {
        Sid      = "GitHub"
        Effect   = "Allow"
        Action   = ["codestar-connections:UseConnection", "codeconnections:UseConnection"]
        Resource = aws_codestarconnections_connection.github.arn
      },
      {
        Sid      = "CodeBuild"
        Effect   = "Allow"
        Action   = ["codebuild:StartBuild", "codebuild:BatchGetBuilds"]
        Resource = [aws_codebuild_project.api_test.arn, aws_codebuild_project.api_build.arn, aws_codebuild_project.web.arn]
      },
      {
        # RegisterTaskDefinition / Describe* nu au permisiuni la nivel de resursă.
        Sid    = "EcsDeploy"
        Effect = "Allow"
        Action = [
          "ecs:DescribeServices", "ecs:DescribeTaskDefinition", "ecs:DescribeTasks", "ecs:ListTasks",
          "ecs:RegisterTaskDefinition", "ecs:TagResource", "ecs:UpdateService",
        ]
        Resource = "*"
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
