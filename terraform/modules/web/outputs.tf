output "ecr_repository_url" {
  value = aws_ecr_repository.web.repository_url
}

output "ecr_repository_arn" {
  value = aws_ecr_repository.web.arn
}

output "service_name" {
  value = aws_ecs_service.web.name
}

output "task_execution_role_arn" {
  value = aws_iam_role.execution.arn
}
