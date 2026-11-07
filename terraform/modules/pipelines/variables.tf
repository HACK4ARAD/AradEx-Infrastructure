variable "github_owner" {
  type = string
}

variable "backend_repo" {
  type = string
}

variable "frontend_repo" {
  type = string
}

variable "branch" {
  type = string
}

variable "domain_name" {
  description = "Folosit pentru VITE_API_URL (absolut: client.ts face new URL(...))."
  type        = string
}

variable "ecr_repository_url" {
  type = string
}

variable "ecr_repository_arn" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "service_name" {
  type = string
}

variable "task_execution_role_arn" {
  description = "Rolurile taskului: deploy-ul ECS trebuie să le poată pasa (iam:PassRole)."
  type        = string
}

variable "task_role_arn" {
  type = string
}

variable "bucket_name" {
  type = string
}

variable "bucket_arn" {
  type = string
}

variable "distribution_id" {
  type = string
}

variable "distribution_arn" {
  type = string
}
