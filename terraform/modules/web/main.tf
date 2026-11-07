# PWA-ul (build-ul Vite) servit de nginx pe Fargate, în spatele ALB-ului (fără CloudFront: contul nu are acces la el).
# Imaginea o construiește AradEx-Frontend/.github/workflows/deploy.yml din deploy/Dockerfile + deploy/nginx.conf.

locals {
  container_definitions = [{
    name         = "web"
    image        = "${aws_ecr_repository.web.repository_url}:latest"
    essential    = true
    portMappings = [{ containerPort = 80, protocol = "tcp" }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.web.name
        awslogs-region        = "eu-north-1"
        awslogs-stream-prefix = "web"
      }
    }
  }]

  container = jsondecode(aws_ecs_task_definition.web.container_definitions)[0]
}

resource "aws_ecr_repository" "web" {
  name                 = "aradex-web"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

resource "aws_ecr_lifecycle_policy" "web" {
  repository = aws_ecr_repository.web.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "păstrează ultimele 10 imagini"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 10 }
      action       = { type = "expire" }
    }]
  })
}

resource "aws_cloudwatch_log_group" "web" {
  name              = "/aradex/web"
  retention_in_days = 7
}

resource "aws_iam_role" "execution" {
  name = "aradex-web-execution"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = "712710404828" } }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_task_definition" "web" {
  family                   = "aradex-web"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.execution.arn
  container_definitions    = jsonencode(local.container_definitions)

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }
}

# ECS refuză un serviciu cu target group nelegat de un listener: îl creăm după listener-ul HTTPS.
resource "terraform_data" "listener" {
  input = var.listener_arn
}

resource "aws_ecs_service" "web" {
  name                               = "aradex-web"
  cluster                            = var.cluster_arn
  task_definition                    = aws_ecs_task_definition.web.arn
  desired_count                      = var.desired_count
  launch_type                        = "FARGATE"
  health_check_grace_period_seconds  = 30
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.public_subnet_ids
    security_groups  = [var.web_sg_id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "web"
    container_port   = 80
  }

  depends_on = [terraform_data.listener]
}
