# Postgres 16 izolat + secretele aplicației.
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

resource "aws_secretsmanager_secret" "openai" {
  name                    = "aradex/openai"
  description             = "OPENAI_API_KEY - valoarea reală se pune cu scripts/set-openai-key.sh"
  recovery_window_in_days = 0
}

# Placeholder intenționat. Cheia reală o pune Zoltan cu scriptul; Terraform nu o suprascrie și nu o vede.
resource "aws_secretsmanager_secret_version" "openai" {
  secret_id     = aws_secretsmanager_secret.openai.id
  secret_string = "REPLACE_ME"

  lifecycle {
    ignore_changes = [secret_string]
  }
}
