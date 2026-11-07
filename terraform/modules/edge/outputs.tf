output "name_servers" {
  description = "Sunt deja la registrar (Hostinger)."
  value       = aws_route53_zone.this.name_servers
}

output "certificate_arn" {
  description = "Certificatul validat, pentru listener-ul HTTPS al ALB-ului."
  value       = aws_acm_certificate_validation.alb.certificate_arn
}

output "site_url" {
  value = "https://${var.domain_name}"
}
