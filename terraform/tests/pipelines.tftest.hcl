mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::712710404828:role/mock" }
  }
  mock_resource "aws_codestarconnections_connection" {
    defaults = { arn = "arn:aws:codestar-connections:eu-north-1:712710404828:connection/mock", id = "arn:aws:codestar-connections:eu-north-1:712710404828:connection/mock" }
  }
  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::aradex-artifacts-mock", bucket = "aradex-artifacts-mock", id = "aradex-artifacts-mock" }
  }
  mock_resource "aws_codebuild_project" {
    defaults = { arn = "arn:aws:codebuild:eu-north-1:712710404828:project/mock" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:eu-north-1:712710404828:log-group:/aradex/codebuild" }
  }
}

variables {
  github_owner            = "HACK4ARAD"
  backend_repo            = "AradEx-Backend"
  frontend_repo           = "AradEx-Frontend"
  branch                  = "main"
  domain_name             = "aradex.example"
  ecr_repository_url      = "712710404828.dkr.ecr.eu-north-1.amazonaws.com/aradex-api"
  ecr_repository_arn      = "arn:aws:ecr:eu-north-1:712710404828:repository/aradex-api"
  cluster_name            = "aradex"
  service_name            = "aradex-api"
  task_execution_role_arn = "arn:aws:iam::712710404828:role/aradex-api-execution"
  task_role_arn           = "arn:aws:iam::712710404828:role/aradex-api-task"
  bucket_name             = "aradex-site-mock"
  bucket_arn              = "arn:aws:s3:::aradex-site-mock"
  distribution_id         = "EMOCK123"
  distribution_arn        = "arn:aws:cloudfront::712710404828:distribution/EMOCK123"
}

run "pipelines" {
  command = apply
  module {
    source = "./modules/pipelines"
  }

  # --- buildspec-uri ---
  assert {
    condition = alltrue([for s in [
      "corretto21", "chmod +x gradlew", "./gradlew test --no-daemon",
      "TESTCONTAINERS_HUB_IMAGE_NAME_PREFIX: public.ecr.aws/docker/library/",
      "TESTCONTAINERS_RYUK_DISABLED: \"true\"", "build/test-results/test",
    ] : strcontains(aws_codebuild_project.api_test.source[0].buildspec, s)])
    error_message = "api test buildspec"
  }
  assert {
    condition = alltrue([for s in [
      "docker pull public.ecr.aws/docker/library/gradle:8.14-jdk21",
      "docker tag public.ecr.aws/docker/library/gradle:8.14-jdk21 gradle:8.14-jdk21",
      "docker pull public.ecr.aws/docker/library/eclipse-temurin:21-jre",
      "docker tag public.ecr.aws/docker/library/eclipse-temurin:21-jre eclipse-temurin:21-jre",
      "$CODEBUILD_RESOLVED_SOURCE_VERSION", "imagedefinitions.json", "\"name\":\"api\"",
    ] : strcontains(aws_codebuild_project.api_build.source[0].buildspec, s)]) && !strcontains(aws_codebuild_project.api_build.source[0].buildspec, "--pull")
    error_message = "api build buildspec (ECR Public mirror, no --pull)"
  }
  # Review Focus 3: index.html / sw.js etc. fără cache lung.
  assert {
    condition = alltrue([for s in [
      "nodejs: 22", "npm ci", "npm run build", "max-age=31536000, immutable", "no-cache",
      "index.html", "sw.js", "registerSW.js", "manifest.webmanifest", "workbox-", "create-invalidation",
    ] : strcontains(aws_codebuild_project.web.source[0].buildspec, s)])
    error_message = "web buildspec"
  }

  # --- conexiune + pipeline-uri ---
  assert {
    condition     = aws_codestarconnections_connection.github.provider_type == "GitHub" && aws_codestarconnections_connection.github.name == "aradex-github"
    error_message = "github connection"
  }
  assert {
    condition = (
      aws_codepipeline.backend.name == "aradex-backend" && aws_codepipeline.backend.pipeline_type == "V2" &&
      tolist([for s in aws_codepipeline.backend.stage : s.name]) == tolist(["Source", "Test", "Build", "Deploy"]) &&
      aws_codepipeline.backend.stage[3].action[0].provider == "ECS" &&
      aws_codepipeline.backend.stage[0].action[0].configuration.FullRepositoryId == "HACK4ARAD/AradEx-Backend"
    )
    error_message = "backend pipeline"
  }
  assert {
    condition = (
      aws_codepipeline.frontend.name == "aradex-frontend" && aws_codepipeline.frontend.pipeline_type == "V2" &&
      tolist([for s in aws_codepipeline.frontend.stage : s.name]) == tolist(["Source", "BuildAndPublish"]) &&
      aws_codepipeline.frontend.stage[0].action[0].configuration.FullRepositoryId == "HACK4ARAD/AradEx-Frontend"
    )
    error_message = "frontend pipeline"
  }
  assert {
    condition = alltrue([for p in [aws_codepipeline.backend, aws_codepipeline.frontend] :
    contains(tolist(one(one(one(one(p.trigger).git_configuration).push).branches).includes), "main")])
    error_message = "push trigger on main"
  }
  assert {
    condition = alltrue([for p in [aws_codebuild_project.api_test, aws_codebuild_project.api_build] :
      p.environment[0].type == "ARM_CONTAINER" &&
      p.environment[0].image == "aws/codebuild/amazonlinux-aarch64-standard:3.0" &&
    p.environment[0].privileged_mode])
    error_message = "api builds on ARM, privileged"
  }
  assert {
    condition = (
      aws_codebuild_project.web.environment[0].image == "aws/codebuild/standard:7.0" &&
      { for v in aws_codebuild_project.web.environment[0].environment_variable : v.name => v.value }["VITE_API_URL"] == "https://aradex.example/api/v1" &&
      { for v in aws_codebuild_project.web.environment[0].environment_variable : v.name => v.value }["VITE_DEMO"] == "true" &&
      { for v in aws_codebuild_project.web.environment[0].environment_variable : v.name => v.value }["BUCKET"] == "aradex-site-mock" &&
      { for v in aws_codebuild_project.web.environment[0].environment_variable : v.name => v.value }["DISTRIBUTION_ID"] == "EMOCK123"
    )
    error_message = "web build env"
  }
  assert {
    condition     = aws_s3_bucket.artifacts.force_destroy
    error_message = "artifacts bucket force_destroy"
  }
  assert {
    condition     = output.backend_pipeline_name == "aradex-backend" && output.frontend_pipeline_name == "aradex-frontend"
    error_message = "outputs"
  }
}
