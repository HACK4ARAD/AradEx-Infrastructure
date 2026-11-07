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

output "web_ecr_repository_url" {
  value = one(module.web[*].ecr_repository_url)
}

output "alb_dns_name" {
  value = module.api.alb_dns_name
}

output "gha_backend_user" {
  description = "Utilizatorul IAM al workflow-ului AradEx-Backend (cheile: scripts/github-keys.sh api)."
  value       = module.github_deploy.backend_user
}

output "gha_frontend_user" {
  description = "Utilizatorul IAM al workflow-ului AradEx-Frontend (cheile: scripts/github-keys.sh web)."
  value       = module.github_deploy.frontend_user
}

output "media_bucket" {
  description = "Bucket-ul S3 cu pozele încărcate din panou (privat; servite de API)."
  value       = module.api.media_bucket
}
