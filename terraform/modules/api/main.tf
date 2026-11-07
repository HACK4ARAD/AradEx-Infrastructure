# ECR + Fargate (ARM, 1 task) în spatele unui ALB intern. CloudFront ajunge la ALB prin VPC origin (modulul edge).

locals {
  container_name = "api"
  container_port = 8080
  health_path    = "/api/v1/health"

  container_definitions = [{
    name         = local.container_name
    image        = "${aws_ecr_repository.api.repository_url}:latest"
    essential    = true
    portMappings = [{ containerPort = local.container_port, protocol = "tcp" }]
    environment = [
      { name = "SPRING_PROFILES_ACTIVE", value = "prod" },
      { name = "OPENAI_MODEL", value = "gpt-4o-mini" },
      { name = "CORS_ORIGINS", value = var.domain_name != "" ? "https://${var.domain_name}" : "http://localhost:5173" },
      # RDS are rds.force_ssl=1, deci conexiunea trebuie să ceară SSL.
      { name = "POSTGRES_URL", value = "jdbc:postgresql://${var.db_endpoint}:5432/aradexperience?sslmode=require" },
    ]
    secrets = [
      { name = "POSTGRES_USER", valueFrom = "${var.db_secret_arn}:username::" },
      { name = "POSTGRES_PASSWORD", valueFrom = "${var.db_secret_arn}:password::" },
      { name = "JWT_SECRET", valueFrom = var.jwt_secret_arn },
      { name = "OPENAI_API_KEY", valueFrom = var.openai_secret_arn },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.api.name
        awslogs-region        = "eu-north-1"
        awslogs-stream-prefix = "api"
      }
    }
  }]

  # Ce rulează efectiv (decodat din resursă) — folosit și de teste.
  container = jsondecode(aws_ecs_task_definition.api.container_definitions)[0]
  env       = { for e in local.container.environment : e.name => e.value }
}

resource "aws_ecr_repository" "api" {
  name                 = "aradex-api"
  image_tag_mutability = "MUTABLE" # :latest se mută la fiecare build
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "api" {
  repository = aws_ecr_repository.api.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "păstrează ultimele 10 imagini"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 10 }
      action       = { type = "expire" }
    }]
  })
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/aradex/api"
  retention_in_days = 7
}

resource "aws_ecs_cluster" "this" {
  name = "aradex"
}

resource "aws_ecs_task_definition" "api" {
  family                   = "aradex-api"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn
  container_definitions    = jsonencode(local.container_definitions)

  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }
}

resource "aws_lb" "api" {
  name               = "aradex-api"
  load_balancer_type = "application"
  internal           = true
  subnets            = var.isolated_subnet_ids
  security_groups    = [var.alb_sg_id]
}

resource "aws_lb_target_group" "api" {
  name                 = "aradex-api"
  port                 = local.container_port
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = "10"

  health_check {
    path                = local.health_path
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200"
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.api.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

resource "aws_ecs_service" "api" {
  name                   = "aradex-api"
  cluster                = aws_ecs_cluster.this.id
  task_definition        = aws_ecs_task_definition.api.arn
  desired_count          = var.desired_count
  launch_type            = "FARGATE"
  enable_execute_command = true

  # Spring Boot + Flyway au nevoie de timp la pornire.
  health_check_grace_period_seconds  = 180
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.public_subnet_ids
    security_groups  = [var.task_sg_id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = local.container_name
    container_port   = local.container_port
  }

  depends_on = [aws_lb_listener.http]
}
