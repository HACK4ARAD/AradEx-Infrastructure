# ECR + Fargate (x86_64, 1 task) în spatele ALB-ului public. Cu domeniu: HTTPS pe ALB, /api/* aici, restul la PWA
# (target group-ul web e tot aici; serviciul nginx e în modulul web).

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
      { name = "ANTHROPIC_MODEL", value = var.anthropic_model },
      # http://localhost = originea aplicației Android (Capacitor), care apelează API-ul de producție.
      { name = "CORS_ORIGINS", value = var.domain_name != "" ? "https://${var.domain_name},http://localhost" : "http://localhost:5173" },
      # RDS are rds.force_ssl=1, deci conexiunea trebuie să ceară SSL.
      { name = "POSTGRES_URL", value = "jdbc:postgresql://${var.db_endpoint}:5432/aradexperience?sslmode=require" },
      # Pozele (media.tf). Cu domeniu, URL-ul public al pozelor e fix; fără domeniu API-ul îl ia din cererea curentă.
      { name = "MEDIA_BUCKET", value = aws_s3_bucket.media.bucket },
      { name = "MEDIA_PUBLIC_URL", value = var.domain_name != "" ? "https://${var.domain_name}/api/v1/media" : "" },
    ]
    secrets = [
      { name = "POSTGRES_USER", valueFrom = "${var.db_secret_arn}:username::" },
      { name = "POSTGRES_PASSWORD", valueFrom = "${var.db_secret_arn}:password::" },
      { name = "JWT_SECRET", valueFrom = var.jwt_secret_arn },
      { name = "ANTHROPIC_API_KEY", valueFrom = var.anthropic_secret_arn },
      { name = "GOOGLE_PLACES_API_KEY", valueFrom = var.google_places_secret_arn },
      { name = "TWILIO_ACCOUNT_SID", valueFrom = "${var.twilio_secret_arn}:account_sid::" },
      { name = "TWILIO_AUTH_TOKEN", valueFrom = "${var.twilio_secret_arn}:auth_token::" },
      { name = "TWILIO_VERIFY_SERVICE_SID", valueFrom = "${var.twilio_secret_arn}:verify_service_sid::" },
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
  name       = "aradex"
  depends_on = [aws_iam_service_linked_role.ecs]
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
    cpu_architecture        = "X86_64" # runner-ele GitHub gratuite sunt x86: build nativ
    operating_system_family = "LINUX"
  }
}

resource "aws_lb" "api" {
  name               = "aradex-api"
  load_balancer_type = "application"
  internal           = false
  subnets            = var.public_subnet_ids
  security_groups    = [var.alb_sg_id]
  idle_timeout       = 60 # apelurile AI pot dura zeci de secunde
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

# Cu domeniu: HTTP -> HTTPS. Fără domeniu: HTTP direct spre API (doar pentru testare).
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.api.arn
  port              = 80
  protocol          = "HTTP"

  dynamic "default_action" {
    for_each = var.enable_https ? [1] : []
    content {
      type = "redirect"
      redirect {
        protocol    = "HTTPS"
        port        = "443"
        status_code = "HTTP_301"
      }
    }
  }

  dynamic "default_action" {
    for_each = var.enable_https ? [] : [1]
    content {
      type             = "forward"
      target_group_arn = aws_lb_target_group.api.arn
    }
  }
}

resource "aws_lb_listener" "https" {
  count             = var.enable_https ? 1 : 0
  load_balancer_arn = aws_lb.api.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.certificate_arn

  # Implicit: PWA-ul (nginx). Rutele SPA, fișierele statice și cache-ul le gestionează nginx.
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web[0].arn
  }
}

# Ținta PWA-ului (serviciul nginx din modulul web se înregistrează aici). Stă lângă ALB ca rutarea să fie într-un loc.
resource "aws_lb_target_group" "web" {
  count                = var.enable_https ? 1 : 0
  name                 = "aradex-web"
  port                 = 80
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = "10"

  health_check {
    path                = "/healthz"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
    matcher             = "200"
  }
}

# www -> domeniul principal (același path și query).
resource "aws_lb_listener_rule" "www" {
  count        = var.enable_https ? 1 : 0
  listener_arn = aws_lb_listener.https[0].arn
  priority     = 1

  condition {
    host_header {
      values = ["www.${var.domain_name}"]
    }
  }

  action {
    type = "redirect"
    redirect {
      host        = var.domain_name
      protocol    = "HTTPS"
      port        = "443"
      status_code = "HTTP_301"
    }
  }
}

# API + Swagger la Spring: erorile rămân ProblemDetail JSON, Authorization/body/toate metodele trec neschimbate.
resource "aws_lb_listener_rule" "api" {
  count        = var.enable_https ? 1 : 0
  listener_arn = aws_lb_listener.https[0].arn
  priority     = 10

  condition {
    path_pattern {
      values = ["/api/*", "/swagger-ui*", "/v3/api-docs*"]
    }
  }

  action {
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

  depends_on = [aws_lb_listener.http, aws_lb_listener_rule.api, aws_iam_service_linked_role.ecs]
}
