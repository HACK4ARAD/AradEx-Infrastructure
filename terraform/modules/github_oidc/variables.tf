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
  description = "Singurul branch care poate asuma rolurile."
  type        = string
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
  description = "Deploy-ul înregistrează task definition-uri noi, deci trebuie să paseze rolurile taskului."
  type        = string
}

variable "task_role_arn" {
  type = string
}

variable "enable_frontend" {
  description = "Rolul FE și parametrii SSM există doar după ce există domeniul (edge)."
  type        = bool
}

variable "bucket_name" {
  type    = string
  default = null
}

variable "bucket_arn" {
  type    = string
  default = null
}

variable "distribution_id" {
  type    = string
  default = null
}

variable "distribution_arn" {
  type    = string
  default = null
}

variable "api_url" {
  description = "VITE_API_URL pentru build-ul FE (https://<domeniu>/api/v1)."
  type        = string
  default     = null
}
