output "connection_arn" {
  description = "Conexiunea GitHub; se activează o dată din consolă."
  value       = aws_codestarconnections_connection.github.arn
}

output "backend_pipeline_name" {
  value = aws_codepipeline.backend.name
}

output "frontend_pipeline_name" {
  value = aws_codepipeline.frontend.name
}

output "backend_pipeline_arn" {
  value = aws_codepipeline.backend.arn
}

output "frontend_pipeline_arn" {
  value = aws_codepipeline.frontend.arn
}
