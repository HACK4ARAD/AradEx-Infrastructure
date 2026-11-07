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
  description = "Branch-ul de deploy (folosit de workflow-uri; cheile nu sunt legate de branch)."
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

variable "web_ecr_repository_arn" {
  type    = string
  default = null
}

variable "web_service_name" {
  type    = string
  default = null
}

variable "web_task_execution_role_arn" {
  type    = string
  default = null
}

variable "web_task_role_arn" {
  description = "Rolul aplicației web (nginx nu are; poate fi null)."
  type        = string
  default     = null
}

variable "api_url" {
  description = "VITE_API_URL pentru build-ul FE (https://<domeniu>/api/v1)."
  type        = string
  default     = null
}
