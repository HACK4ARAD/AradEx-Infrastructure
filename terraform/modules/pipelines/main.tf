# Două CodePipeline V2, declanșate de push pe main prin CodeConnections:
#   aradex-backend:  Source -> Test (gradle test) -> Build (docker -> ECR) -> Deploy (ECS rolling, rollback automat)
#   aradex-frontend: Source -> BuildAndPublish (vite build -> S3 -> invalidare CloudFront)

locals {
  ecr_registry = split("/", var.ecr_repository_url)[0]

  arm_image = "aws/codebuild/amazonlinux-aarch64-standard:3.0"
  x86_image = "aws/codebuild/standard:7.0"
}

# Rămâne PENDING până o activează Zoltan din consolă (instalează aplicația GitHub pe HACK4ARAD).
resource "aws_codestarconnections_connection" "github" {
  name          = "aradex-github"
  provider_type = "GitHub"
}

resource "aws_s3_bucket" "artifacts" {
  bucket_prefix = "aradex-artifacts-"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/aradex/codebuild"
  retention_in_days = 7
}

# --- CodeBuild -------------------------------------------------------------

resource "aws_codebuild_project" "api_test" {
  name          = "aradex-api-test"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 20

  source {
    type      = "CODEPIPELINE"
    buildspec = file("${path.module}/buildspecs/api-test.yml")
  }

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    type            = "ARM_CONTAINER"
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = local.arm_image
    privileged_mode = true # Docker pentru Testcontainers
  }

  cache {
    type  = "LOCAL"
    modes = ["LOCAL_CUSTOM_CACHE", "LOCAL_DOCKER_LAYER_CACHE"]
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.codebuild.name
      stream_name = "api-test"
    }
  }
}

resource "aws_codebuild_project" "api_build" {
  name          = "aradex-api-build"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 20

  source {
    type      = "CODEPIPELINE"
    buildspec = file("${path.module}/buildspecs/api-build.yml")
  }

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    type            = "ARM_CONTAINER"
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = local.arm_image
    privileged_mode = true # docker build

    environment_variable {
      name  = "ECR_REPOSITORY_URL"
      value = var.ecr_repository_url
    }
    environment_variable {
      name  = "ECR_REGISTRY"
      value = local.ecr_registry
    }
  }

  cache {
    type  = "LOCAL"
    modes = ["LOCAL_CUSTOM_CACHE", "LOCAL_DOCKER_LAYER_CACHE"]
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.codebuild.name
      stream_name = "api-build"
    }
  }
}

resource "aws_codebuild_project" "web" {
  name          = "aradex-web"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 15

  source {
    type      = "CODEPIPELINE"
    buildspec = file("${path.module}/buildspecs/web.yml")
  }

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    type         = "LINUX_CONTAINER"
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = local.x86_image

    environment_variable {
      name  = "VITE_API_URL"
      value = "https://${var.domain_name}/api/v1"
    }
    environment_variable {
      name  = "VITE_DEMO"
      value = "true"
    }
    environment_variable {
      name  = "BUCKET"
      value = var.bucket_name
    }
    environment_variable {
      name  = "DISTRIBUTION_ID"
      value = var.distribution_id
    }
  }

  cache {
    type  = "LOCAL"
    modes = ["LOCAL_CUSTOM_CACHE"]
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.codebuild.name
      stream_name = "web"
    }
  }
}

# --- CodePipeline ----------------------------------------------------------

resource "aws_codepipeline" "backend" {
  name          = "aradex-backend"
  pipeline_type = "V2"
  role_arn      = aws_iam_role.codepipeline.arn

  artifact_store {
    type     = "S3"
    location = aws_s3_bucket.artifacts.bucket
  }

  trigger {
    provider_type = "CodeStarSourceConnection"
    git_configuration {
      source_action_name = "Source"
      push {
        branches {
          includes = [var.branch]
        }
      }
    }
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source"]
      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github.arn
        FullRepositoryId = "${var.github_owner}/${var.backend_repo}"
        BranchName       = var.branch
      }
    }
  }

  stage {
    name = "Test"
    action {
      name            = "GradleTest"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["source"]
      configuration   = { ProjectName = aws_codebuild_project.api_test.name }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "DockerBuild"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source"]
      output_artifacts = ["image"]
      configuration    = { ProjectName = aws_codebuild_project.api_build.name }
    }
  }

  stage {
    name = "Deploy"
    action {
      name            = "EcsDeploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "ECS"
      version         = "1"
      input_artifacts = ["image"]
      configuration = {
        ClusterName       = var.cluster_name
        ServiceName       = var.service_name
        FileName          = "imagedefinitions.json"
        DeploymentTimeout = "15"
      }
    }
  }
}

resource "aws_codepipeline" "frontend" {
  name          = "aradex-frontend"
  pipeline_type = "V2"
  role_arn      = aws_iam_role.codepipeline.arn

  artifact_store {
    type     = "S3"
    location = aws_s3_bucket.artifacts.bucket
  }

  trigger {
    provider_type = "CodeStarSourceConnection"
    git_configuration {
      source_action_name = "Source"
      push {
        branches {
          includes = [var.branch]
        }
      }
    }
  }

  stage {
    name = "Source"
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source"]
      configuration = {
        ConnectionArn    = aws_codestarconnections_connection.github.arn
        FullRepositoryId = "${var.github_owner}/${var.frontend_repo}"
        BranchName       = var.branch
      }
    }
  }

  stage {
    name = "BuildAndPublish"
    action {
      name            = "ViteBuildToS3"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["source"]
      configuration   = { ProjectName = aws_codebuild_project.web.name }
    }
  }
}
