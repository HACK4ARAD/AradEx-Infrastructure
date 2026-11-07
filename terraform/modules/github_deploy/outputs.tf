output "backend_user" {
  description = "Utilizatorul IAM folosit de AradEx-Backend/.github/workflows/deploy.yml"
  value       = aws_iam_user.backend.name
}

output "frontend_user" {
  description = "Utilizatorul IAM folosit de AradEx-Frontend/.github/workflows/deploy.yml (null fără domeniu)"
  value       = one(aws_iam_user.frontend[*].name)
}
