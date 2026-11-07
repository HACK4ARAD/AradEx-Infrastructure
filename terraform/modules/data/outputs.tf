output "db_endpoint" {
  description = "Adresa RDS, fără port."
  value       = aws_db_instance.this.address
}

output "db_instance_id" {
  value = aws_db_instance.this.identifier
}

output "db_secret_arn" {
  description = "Secretul gestionat de RDS (chei: username, password)."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "jwt_secret_arn" {
  value = aws_secretsmanager_secret.jwt.arn
}

output "anthropic_secret_arn" {
  value = aws_secretsmanager_secret.anthropic.arn
}

output "google_places_secret_arn" {
  value = aws_secretsmanager_secret.google_places.arn
}

output "twilio_secret_arn" {
  value = aws_secretsmanager_secret.twilio.arn
}

output "sms_gateway_secret_arn" {
  value = aws_secretsmanager_secret.sms_gateway.arn
}
