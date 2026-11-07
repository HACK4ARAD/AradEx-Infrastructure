output "ecr_repository_url" {
  value = module.api.ecr_repository_url
}

output "cluster_name" {
  value = module.api.cluster_name
}

output "service_name" {
  value = module.api.service_name
}

output "name_servers" {
  description = "Nameserverele de pus la registrar (după ce domain_name e setat)."
  value       = one(module.edge[*].name_servers)
}

output "site_url" {
  value = one(module.edge[*].site_url)
}

output "bucket_name" {
  value = one(module.edge[*].bucket_name)
}

output "distribution_id" {
  value = one(module.edge[*].distribution_id)
}

output "gha_backend_role_arn" {
  description = "role-to-assume pentru workflow-ul AradEx-Backend."
  value       = module.github_oidc.backend_role_arn
}

output "gha_frontend_role_arn" {
  description = "role-to-assume pentru workflow-ul AradEx-Frontend (după ce există domeniul)."
  value       = module.github_oidc.frontend_role_arn
}
