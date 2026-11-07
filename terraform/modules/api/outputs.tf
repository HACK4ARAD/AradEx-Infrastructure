output "ecr_repository_url" {
  value = aws_ecr_repository.api.repository_url
}

output "ecr_repository_arn" {
  value = aws_ecr_repository.api.arn
}

output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "service_name" {
  value = aws_ecs_service.api.name
}

output "alb_arn" {
  value = aws_lb.api.arn
}

output "cluster_arn" {
  value = aws_ecs_cluster.this.arn
}

output "alb_zone_id" {
  value = aws_lb.api.zone_id
}

output "web_target_group_arn" {
  value = one(aws_lb_target_group.web[*].arn)
}

output "web_target_group_arn_suffix" {
  value = one(aws_lb_target_group.web[*].arn_suffix)
}

output "https_listener_arn" {
  value = one(aws_lb_listener.https[*].arn)
}

output "alb_dns_name" {
  value = aws_lb.api.dns_name
}

output "alb_arn_suffix" {
  value = aws_lb.api.arn_suffix
}

output "target_group_arn_suffix" {
  value = aws_lb_target_group.api.arn_suffix
}

output "task_execution_role_arn" {
  value = aws_iam_role.execution.arn
}

output "task_role_arn" {
  value = aws_iam_role.task.arn
}
