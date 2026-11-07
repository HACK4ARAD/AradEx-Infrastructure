variable "domain_name" {
  description = "Domeniul (apex). www.<domeniu> se redirecționează spre el."
  type        = string
}

variable "alb_arn" {
  description = "ALB-ul intern al API-ului (origin VPC)."
  type        = string
}

variable "alb_dns_name" {
  description = "Numele DNS intern al ALB-ului."
  type        = string
}
