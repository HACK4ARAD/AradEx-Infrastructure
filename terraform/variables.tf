variable "domain_name" {
  description = "Domeniul cumpărat extern (ex. aradexperience.ro). Gol = edge și pipelines nu se creează încă."
  type        = string
  default     = ""

  validation {
    condition     = var.domain_name == "" || can(regex("^[a-z0-9-]+(\\.[a-z0-9-]+)+$", var.domain_name))
    error_message = "domain_name trebuie să fie gol sau un domeniu valid, cu litere mici (ex. aradexperience.ro)."
  }
}

variable "alert_email" {
  description = "Unde merg alertele (SNS, buget). Se pune în local.auto.tfvars (ignorat de git)."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+$", var.alert_email))
    error_message = "alert_email trebuie să fie o adresă de email."
  }
}

variable "api_desired_count" {
  description = "Câte taskuri API rulează: 0 până există o imagine în ECR, apoi 1."
  type        = number
  default     = 0

  validation {
    condition     = contains([0, 1], var.api_desired_count)
    error_message = "api_desired_count trebuie să fie 0 sau 1."
  }
}

variable "github_owner" {
  description = "Organizația GitHub cu repo-urile de cod."
  type        = string
  default     = "HACK4ARAD"
}

variable "backend_repo" {
  description = "Repo-ul backend-ului (Spring Boot)."
  type        = string
  default     = "AradEx-Backend"
}

variable "frontend_repo" {
  description = "Repo-ul frontend-ului (Vue PWA)."
  type        = string
  default     = "AradEx-Frontend"
}

variable "branch" {
  description = "Branch-ul care declanșează deploy-ul."
  type        = string
  default     = "main"
}
