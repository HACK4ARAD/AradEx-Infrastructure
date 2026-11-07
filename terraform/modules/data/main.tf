# Postgres 16 izolat + secretele aplicației (JWT generat; cheia Claude API pusă manual de Zoltan).
terraform {
  required_providers {
    aws    = { source = "hashicorp/aws" }
    random = { source = "hashicorp/random" }
  }
}

resource "aws_db_subnet_group" "this" {
  name       = "aradex"
  subnet_ids = var.isolated_subnet_ids
}

resource "aws_db_parameter_group" "this" {
  name   = "aradex-postgres16"
  family = "postgres16"

  # Parametru static: RDS îl salvează ca pending-reboot; altfel planul ar arăta mereu o diferență.
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }
}

resource "aws_db_instance" "this" {
  identifier     = "aradex"
  engine         = "postgres"
  engine_version = "16" # RDS alege ultima versiune minoră 16.x
  instance_class = "db.t4g.micro"

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name                     = "aradexperience"
  username                    = "arad"
  manage_master_user_password = true # parola stă în Secrets Manager, gestionată de RDS

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.db_sg_id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false
  multi_az               = false

  # Planul gratuit AWS limitează retenția; 1 zi ajunge pentru un weekend.
  backup_retention_period   = 1
  deletion_protection       = false
  skip_final_snapshot       = false
  final_snapshot_identifier = "aradex-final"
  apply_immediately         = true
}

resource "random_password" "jwt" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "jwt" {
  name                    = "aradex/jwt"
  description             = "JWT_SECRET pentru API"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "jwt" {
  secret_id     = aws_secretsmanager_secret.jwt.id
  secret_string = random_password.jwt.result
}

resource "aws_secretsmanager_secret" "anthropic" {
  name                    = "aradex/anthropic"
  description             = "ANTHROPIC_API_KEY (Claude API) - valoarea reala se pune cu scripts/set-anthropic-key.sh"
  recovery_window_in_days = 0
}

# Placeholder intenționat. Cheia reală o pune Zoltan cu scriptul; Terraform nu o suprascrie și nu o vede.
resource "aws_secretsmanager_secret_version" "anthropic" {
  secret_id     = aws_secretsmanager_secret.anthropic.id
  secret_string = "REPLACE_ME"

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# T17 (opțional): cheia Google Places API (New) pentru rating + recenzii Google, folosită doar de backend.
# Placeholder intenționat; valoarea reală o pune Zoltan cu scripts/set-google-places-key.sh.
resource "aws_secretsmanager_secret" "google_places" {
  name                    = "aradex/google-places"
  description             = "GOOGLE_PLACES_API_KEY (T17) - valoarea reala se pune cu scripts/set-google-places-key.sh"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "google_places" {
  secret_id     = aws_secretsmanager_secret.google_places.id
  secret_string = "REPLACE_ME"

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# T21: Twilio Verify, SMS-ul cu codul OTP pentru conturile personale (numerele de demo 0799000xxx nu primesc SMS).
# SMS-ul prin AWS (SNS / End User Messaging) e blocat de SCP-ul contului. JSON cu chei goale ca placeholder:
# backend-ul răspunde 503 „SMS unavailable” până pune Zoltan valorile cu scripts/set-twilio-keys.sh.
resource "aws_secretsmanager_secret" "twilio" {
  name                    = "aradex/twilio"
  description             = "Twilio Verify (T21): account_sid, auth_token, verify_service_sid - se pun cu scripts/set-twilio-keys.sh"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "twilio" {
  secret_id     = aws_secretsmanager_secret.twilio.id
  secret_string = jsonencode({ account_sid = "", auth_token = "", verify_service_sid = "" })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# T24: SMS-urile OTP trimise de pe telefonul lui Zoltan (Mac + iPhone, AradEx-Ops/sms-gateway). Tokenul cu care scriptul
# de pe Mac ia SMS-urile din coada API-ului; îl generează și îl pune AradEx-Ops/sms-gateway/setup.sh. Gol = gateway oprit
# (numerele reale merg prin Twilio).
resource "aws_secretsmanager_secret" "sms_gateway" {
  name                    = "aradex/sms-gateway"
  description             = "Tokenul gateway-ului de SMS (T24): JSON {token} - îl pune AradEx-Ops/sms-gateway/setup.sh"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "sms_gateway" {
  secret_id     = aws_secretsmanager_secret.sms_gateway.id
  secret_string = jsonencode({ token = "" })

  lifecycle {
    ignore_changes = [secret_string]
  }
}

