locals {
  ecs_tasks_trust = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = "712710404828" } }
    }]
  })
}

# Rolul de execuție: ECS trage imaginea, scrie loguri și citește secretele la pornirea taskului.
resource "aws_iam_role" "execution" {
  name               = "aradex-api-execution"
  assume_role_policy = local.ecs_tasks_trust
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "execution_secrets" {
  name = "read-app-secrets"
  role = aws_iam_role.execution.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = [var.db_secret_arn, var.jwt_secret_arn, var.anthropic_secret_arn, var.google_places_secret_arn, var.twilio_secret_arn]
    }]
  })
}

# Rolul aplicației: doar ECS Exec (depanare cu `aws ecs execute-command`).
resource "aws_iam_role" "task" {
  name               = "aradex-api-task"
  assume_role_policy = local.ecs_tasks_trust
}

resource "aws_iam_role_policy" "task_exec_command" {
  name = "ecs-exec"
  role = aws_iam_role.task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel",
      ]
      Resource = "*"
    }]
  })
}

# Cont nou: rolul service-linked ECS nu există încă. Îl creăm explicit, înaintea clusterului și a serviciului,
# altfel CreateService poate pica cu "Unable to assume the service linked role".
resource "aws_iam_service_linked_role" "ecs" {
  aws_service_name = "ecs.amazonaws.com"
}
