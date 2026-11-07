variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  description = "Subneturile în care rulează taskurile (IP public doar pentru ieșire)."
  type        = list(string)
}

variable "isolated_subnet_ids" {
  description = "Subneturile ALB-ului intern."
  type        = list(string)
}

variable "alb_sg_id" {
  type = string
}

variable "task_sg_id" {
  type = string
}

variable "db_endpoint" {
  description = "Adresa RDS, fără port."
  type        = string
}

variable "db_secret_arn" {
  description = "Secretul gestionat de RDS (chei: username, password)."
  type        = string
}

variable "jwt_secret_arn" {
  type = string
}

variable "openai_secret_arn" {
  type = string
}

variable "domain_name" {
  description = "Fără domeniu (încă necumpărat), CORS rămâne pe localhost."
  type        = string
  default     = ""
}

variable "desired_count" {
  description = "0 până există o imagine în ECR, apoi 1."
  type        = number
  default     = 0
}

variable "enable_https" {
  description = "Cu domeniu: HTTP redirecționează spre HTTPS, iar HTTPS rutează /api/* spre API și restul spre web."
  type        = bool
  default     = false
}

variable "certificate_arn" {
  description = "Certificatul ACM (eu-north-1, validat) pentru listener-ul HTTPS."
  type        = string
  default     = null
}
