output "backend_role_arn" {
  description = "role-to-assume în AradEx-Backend/.github/workflows/deploy.yml"
  value       = aws_iam_role.backend.arn
}

output "frontend_role_arn" {
  description = "role-to-assume în AradEx-Frontend/.github/workflows/deploy.yml (null fără domeniu)"
  value       = one(aws_iam_role.frontend[*].arn)
}
