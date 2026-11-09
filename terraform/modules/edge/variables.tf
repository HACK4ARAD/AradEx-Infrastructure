variable "domain_name" {
  description = "Domeniul (apex). www.<domeniu> se redirecționează spre el (regula din ALB)."
  type        = string
}

variable "alb_dns_name" {
  description = "Numele DNS public al ALB-ului."
  type        = string
}

variable "alb_zone_id" {
  description = "Zona Route 53 a ALB-ului (pentru înregistrările alias)."
  type        = string
}

variable "google_site_verification" {
  description = "Codul Google Search Console (google-site-verification=…), TXT pe apex; gol = fără."
  type        = string
  default     = ""
}
