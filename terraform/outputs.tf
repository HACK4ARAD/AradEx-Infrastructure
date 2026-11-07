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
