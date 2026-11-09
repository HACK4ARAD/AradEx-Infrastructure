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

variable "anthropic_model" {
  description = "Modelul Claude folosit de chat și planificator (ANTHROPIC_MODEL)."
  type        = string
  default     = "claude-haiku-5-5"
}

variable "anthropic_secret_arn" {
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

variable "google_places_secret_arn" {
  description = "Cheia Google Places (T17), injectată ca GOOGLE_PLACES_API_KEY; backend-ul o citește abia în T17."
  type        = string
}

variable "stripe_secret_arn" {
  description = "Stripe test mode (T07/T25): secret JSON cu secret_key și publishable_key, injectate ca STRIPE_* (goale = plata demonstrativă); webhook_secret injectat ca STRIPE_WEBHOOK_SECRET (webhook-ul din BE #28)."
  type        = string
}

variable "enable_email" {
  description = "Emailurile prin SES (doar cu domeniu): MAIL_FROM în task + dreptul ses:SendEmail pe identitatea domeniului."
  type        = bool
  default     = false
}

variable "ses_identity_arn" {
  description = "ARN-ul identității SES a domeniului (modulul edge); folosit doar cu enable_email."
  type        = string
  default     = null
}
