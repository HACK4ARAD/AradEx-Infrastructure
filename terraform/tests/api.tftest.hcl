mock_provider "aws" {
  # Provider-ul validează formatul ARN-urilor și sub mock.
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::712710404828:role/mock" }
  }
  mock_resource "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:eu-north-1:712710404828:loadbalancer/app/aradex-api/0123456789abcdef", arn_suffix = "app/aradex-api/0123456789abcdef" }
  }
  mock_resource "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:eu-north-1:712710404828:targetgroup/aradex-api/0123456789abcdef", arn_suffix = "targetgroup/aradex-api/0123456789abcdef" }
  }
  mock_resource "aws_lb_listener" {
    defaults = { arn = "arn:aws:elasticloadbalancing:eu-north-1:712710404828:listener/app/aradex-api/0123456789abcdef/fedcba9876543210" }
  }
  mock_resource "aws_ecs_task_definition" {
    defaults = { arn = "arn:aws:ecs:eu-north-1:712710404828:task-definition/aradex-api:1" }
  }
  mock_resource "aws_ecs_cluster" {
    defaults = { arn = "arn:aws:ecs:eu-north-1:712710404828:cluster/aradex", id = "arn:aws:ecs:eu-north-1:712710404828:cluster/aradex" }
  }
  override_resource {
    target = aws_ecr_repository.api
    values = { repository_url = "712710404828.dkr.ecr.eu-north-1.amazonaws.com/aradex-api" }
  }
}

variables {
  vpc_id               = "vpc-1"
  public_subnet_ids    = ["subnet-pub-a", "subnet-pub-b"]
  isolated_subnet_ids  = ["subnet-iso-a", "subnet-iso-b"]
  alb_sg_id            = "sg-alb"
  task_sg_id           = "sg-task"
  db_endpoint          = "db.example.internal"
  db_secret_arn        = "arn:aws:secretsmanager:eu-north-1:712710404828:secret:rds-db"
  jwt_secret_arn       = "arn:aws:secretsmanager:eu-north-1:712710404828:secret:aradex/jwt"
  anthropic_secret_arn = "arn:aws:secretsmanager:eu-north-1:712710404828:secret:aradex/anthropic"
  anthropic_model      = "claude-haiku-5-5"
  domain_name          = "aradex.example"
  desired_count        = 0
  enable_https         = true
  certificate_arn      = "arn:aws:acm:eu-north-1:712710404828:certificate/mock"
}

run "api" {
  command = apply
  module {
    source = "./modules/api"
  }

  assert {
    condition     = aws_ecr_repository.api.name == "aradex-api" && aws_ecr_repository.api.force_delete
    error_message = "ecr repo"
  }
  assert {
    condition     = jsondecode(aws_ecr_lifecycle_policy.api.policy).rules[0].selection.countNumber == 10
    error_message = "keep last 10 images"
  }
  assert {
    condition     = aws_ecs_task_definition.api.cpu == "512" && aws_ecs_task_definition.api.memory == "1024" && aws_ecs_task_definition.api.runtime_platform[0].cpu_architecture == "X86_64" && aws_ecs_task_definition.api.requires_compatibilities == toset(["FARGATE"])
    error_message = "task 512/1024 X86_64 Fargate"
  }
  assert {
    condition     = local.container.name == "api" && local.container.portMappings[0].containerPort == 8080 && local.container.image == "712710404828.dkr.ecr.eu-north-1.amazonaws.com/aradex-api:latest"
    error_message = "container name/port/image"
  }
  assert {
    condition     = local.env["SPRING_PROFILES_ACTIVE"] == "prod" && local.env["ANTHROPIC_MODEL"] == "claude-haiku-5-5" && !contains(keys(local.env), "OPENAI_MODEL") && local.env["CORS_ORIGINS"] == "https://aradex.example,http://localhost"
    error_message = "container env"
  }
  # Review Focus 5: RDS are rds.force_ssl=1.
  assert {
    condition     = local.env["POSTGRES_URL"] == "jdbc:postgresql://db.example.internal:5432/aradexperience?sslmode=require"
    error_message = "jdbc url with sslmode=require"
  }
  assert {
    condition     = sort([for s in local.container.secrets : s.name]) == tolist(["ANTHROPIC_API_KEY", "JWT_SECRET", "POSTGRES_PASSWORD", "POSTGRES_USER"])
    error_message = "container secrets"
  }
  assert {
    condition     = [for s in local.container.secrets : s.valueFrom if s.name == "POSTGRES_USER"][0] == "arn:aws:secretsmanager:eu-north-1:712710404828:secret:rds-db:username::"
    error_message = "POSTGRES_USER from RDS secret username key"
  }
  assert {
    condition     = aws_ecs_service.api.name == "aradex-api" && aws_ecs_service.api.desired_count == 0 && aws_ecs_service.api.launch_type == "FARGATE" && aws_ecs_service.api.enable_execute_command
    error_message = "service basics"
  }
  # Review Focus 4: Spring Boot + Flyway pornește încet.
  assert {
    condition     = aws_ecs_service.api.health_check_grace_period_seconds == 180
    error_message = "grace period 180s"
  }
  assert {
    condition     = aws_ecs_service.api.deployment_minimum_healthy_percent == 100 && aws_ecs_service.api.deployment_maximum_percent == 200 && aws_ecs_service.api.deployment_circuit_breaker[0].enable && aws_ecs_service.api.deployment_circuit_breaker[0].rollback
    error_message = "rolling deploy with circuit breaker rollback"
  }
  assert {
    condition     = aws_ecs_service.api.network_configuration[0].assign_public_ip && aws_ecs_service.api.network_configuration[0].subnets == toset(["subnet-pub-a", "subnet-pub-b"]) && aws_ecs_service.api.network_configuration[0].security_groups == toset(["sg-task"])
    error_message = "service networking"
  }
  assert {
    condition     = aws_ecs_cluster.this.name == "aradex"
    error_message = "cluster name"
  }
  assert {
    condition     = !aws_lb.api.internal && aws_lb.api.subnets == toset(["subnet-pub-a", "subnet-pub-b"]) && aws_lb.api.security_groups == toset(["sg-alb"])
    error_message = "public alb in public subnets"
  }
  assert {
    condition = (
      aws_lb_listener.http.port == 80 && aws_lb_listener.http.protocol == "HTTP" &&
      aws_lb_listener.http.default_action[0].type == "redirect" &&
      aws_lb_listener.http.default_action[0].redirect[0].protocol == "HTTPS" &&
      aws_lb_listener.http.default_action[0].redirect[0].port == "443" &&
      aws_lb_listener.http.default_action[0].redirect[0].status_code == "HTTP_301"
    )
    error_message = "http redirects to https"
  }
  assert {
    condition = (
      aws_lb_listener.https[0].port == 443 && aws_lb_listener.https[0].protocol == "HTTPS" &&
      aws_lb_listener.https[0].certificate_arn == var.certificate_arn &&
      aws_lb_listener.https[0].ssl_policy == "ELBSecurityPolicy-TLS13-1-2-2021-06" &&
      aws_lb_listener.https[0].default_action[0].type == "forward" &&
      aws_lb_listener.https[0].default_action[0].target_group_arn == aws_lb_target_group.web[0].arn
    )
    error_message = "https listener: everything else goes to the web (nginx) target group"
  }
  assert {
    condition = (
      aws_lb_target_group.web[0].name == "aradex-web" && aws_lb_target_group.web[0].port == 80 && aws_lb_target_group.web[0].target_type == "ip" &&
      aws_lb_target_group.web[0].health_check[0].path == "/healthz"
    )
    error_message = "web target group with /healthz"
  }
  # Review Focus 1/2: API-ul rămâne la Spring (erori JSON, Authorization, toate metodele) — doar rutare pe path.
  assert {
    condition = (
      aws_lb_listener_rule.api[0].priority == 10 &&
      aws_lb_listener_rule.api[0].action[0].target_group_arn == aws_lb_target_group.api.arn &&
      toset(one(one(aws_lb_listener_rule.api[0].condition).path_pattern).values) == toset(["/api/*", "/swagger-ui*", "/v3/api-docs*"])
    )
    error_message = "api paths go to the api target group"
  }
  assert {
    condition = (
      aws_lb_listener_rule.www[0].priority == 1 &&
      toset(one(one(aws_lb_listener_rule.www[0].condition).host_header).values) == toset(["www.aradex.example"]) &&
      aws_lb_listener_rule.www[0].action[0].redirect[0].host == "aradex.example" &&
      aws_lb_listener_rule.www[0].action[0].redirect[0].status_code == "HTTP_301"
    )
    error_message = "www redirects to apex"
  }
  assert {
    condition     = aws_lb_target_group.api.port == 8080 && aws_lb_target_group.api.target_type == "ip" && aws_lb_target_group.api.deregistration_delay == "10"
    error_message = "target group"
  }
  assert {
    condition     = aws_lb_target_group.api.health_check[0].path == "/api/v1/health" && aws_lb_target_group.api.health_check[0].interval == 15 && aws_lb_target_group.api.health_check[0].healthy_threshold == 2 && aws_lb_target_group.api.health_check[0].unhealthy_threshold == 3
    error_message = "health check"
  }
  assert {
    condition     = aws_cloudwatch_log_group.api.name == "/aradex/api" && aws_cloudwatch_log_group.api.retention_in_days == 7
    error_message = "logs 7 days"
  }
  assert {
    condition     = toset(jsondecode(aws_iam_role_policy.execution_secrets.policy).Statement[0].Resource) == toset([var.db_secret_arn, var.jwt_secret_arn, var.anthropic_secret_arn]) && jsondecode(aws_iam_role_policy.execution_secrets.policy).Statement[0].Action == "secretsmanager:GetSecretValue"
    error_message = "execution role reads only the 3 secrets"
  }
  # Cont nou: fără rolul service-linked ECS, CreateService poate pica imediat după CreateCluster.
  assert {
    condition     = aws_iam_service_linked_role.ecs.aws_service_name == "ecs.amazonaws.com"
    error_message = "ecs service-linked role managed before the service"
  }
  assert {
    condition     = contains(jsondecode(aws_iam_role_policy.task_exec_command.policy).Statement[0].Action, "ssmmessages:OpenDataChannel")
    error_message = "task role allows ECS Exec"
  }
}

run "cors_fallback_without_domain" {
  command = apply
  module {
    source = "./modules/api"
  }
  variables {
    domain_name     = ""
    enable_https    = false
    certificate_arn = null
  }
  assert {
    condition     = local.env["CORS_ORIGINS"] == "http://localhost:5173"
    error_message = "cors fallback"
  }
  assert {
    condition     = length(aws_lb_listener.https) == 0 && length(aws_lb_target_group.web) == 0 && aws_lb_listener.http.default_action[0].type == "forward" && aws_lb_listener.http.default_action[0].target_group_arn == aws_lb_target_group.api.arn
    error_message = "without a domain: plain http straight to the api"
  }
}

run "desired_one" {
  command = apply
  module {
    source = "./modules/api"
  }
  variables {
    desired_count = 1
  }
  assert {
    condition     = aws_ecs_service.api.desired_count == 1
    error_message = "desired 1"
  }
}
