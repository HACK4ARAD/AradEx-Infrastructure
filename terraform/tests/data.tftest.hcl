mock_provider "aws" {
  # În AWS, manage_master_user_password=true populează mereu master_user_secret; mock-ul îl lasă gol.
  override_resource {
    target = aws_db_instance.this
    values = {
      master_user_secret = [{ secret_arn = "arn:aws:secretsmanager:eu-north-1:712710404828:secret:rds!db-mock", kms_key_id = "", secret_status = "active" }]
    }
  }
}

variables {
  isolated_subnet_ids = ["subnet-iso-a", "subnet-iso-b"]
  db_sg_id            = "sg-db"
}

run "data" {
  command = apply
  module {
    source = "./modules/data"
  }

  assert {
    condition     = aws_db_instance.this.engine == "postgres" && startswith(aws_db_instance.this.engine_version, "16") && aws_db_instance.this.instance_class == "db.t4g.micro"
    error_message = "postgres 16 on db.t4g.micro"
  }
  assert {
    condition     = aws_db_instance.this.allocated_storage == 20 && aws_db_instance.this.storage_type == "gp3" && aws_db_instance.this.storage_encrypted
    error_message = "20 GB gp3 encrypted"
  }
  assert {
    condition     = !aws_db_instance.this.multi_az && !aws_db_instance.this.publicly_accessible && aws_db_instance.this.backup_retention_period == 1 && !aws_db_instance.this.deletion_protection
    error_message = "single-az, private, 1 day backup, no deletion protection"
  }
  assert {
    condition     = aws_db_instance.this.db_name == "aradexperience" && aws_db_instance.this.username == "arad" && aws_db_instance.this.manage_master_user_password
    error_message = "db name, user, RDS-managed password"
  }
  assert {
    condition     = !aws_db_instance.this.skip_final_snapshot && aws_db_instance.this.final_snapshot_identifier == "aradex-final"
    error_message = "final snapshot on delete"
  }
  assert {
    condition     = aws_db_instance.this.vpc_security_group_ids == toset(["sg-db"])
    error_message = "db sg"
  }
  assert {
    condition     = aws_db_parameter_group.this.family == "postgres16" && anytrue([for p in aws_db_parameter_group.this.parameter : p.name == "rds.force_ssl" && p.value == "1" && p.apply_method == "pending-reboot"])
    error_message = "force ssl (static parameter: pending-reboot, as RDS stores it)"
  }
  assert {
    condition     = aws_db_subnet_group.this.subnet_ids == toset(["subnet-iso-a", "subnet-iso-b"])
    error_message = "isolated subnets"
  }
  assert {
    condition     = random_password.jwt.length == 64 && !random_password.jwt.special && aws_secretsmanager_secret.jwt.name == "aradex/jwt"
    error_message = "jwt secret"
  }
  assert {
    condition     = aws_secretsmanager_secret.anthropic.name == "aradex/anthropic" && aws_secretsmanager_secret_version.anthropic.secret_string == "REPLACE_ME"
    error_message = "anthropic (Claude API) key placeholder"
  }
  # T17 (opțional): cheia Google Places; valoarea o pune Zoltan cu scripts/set-google-places-key.sh.
  assert {
    condition     = aws_secretsmanager_secret.google_places.name == "aradex/google-places" && aws_secretsmanager_secret_version.google_places.secret_string == "REPLACE_ME" && aws_secretsmanager_secret.google_places.recovery_window_in_days == 0
    error_message = "google places key placeholder"
  }
  # T21: Twilio Verify (SMS-ul OTP); JSON cu chei goale până le pune Zoltan cu scripts/set-twilio-keys.sh.
  assert {
    condition     = aws_secretsmanager_secret.twilio.name == "aradex/twilio"
    error_message = "twilio secret name"
  }
  assert {
    condition     = aws_secretsmanager_secret.twilio.recovery_window_in_days == 0
    error_message = "twilio secret immediate deletion"
  }
  assert {
    condition     = jsonencode(sort(keys(jsondecode(nonsensitive(aws_secretsmanager_secret_version.twilio.secret_string))))) == jsonencode(["account_sid", "auth_token", "verify_service_sid"])
    error_message = "twilio secret placeholder keys"
  }
  # T24: tokenul gateway-ului de SMS (Mac + iPhone); gol până îl pune AradEx-Ops/sms-gateway/setup.sh.
  assert {
    condition     = aws_secretsmanager_secret.sms_gateway.name == "aradex/sms-gateway" && aws_secretsmanager_secret.sms_gateway.recovery_window_in_days == 0
    error_message = "sms gateway secret"
  }
  assert {
    condition     = jsonencode(jsondecode(nonsensitive(aws_secretsmanager_secret_version.sms_gateway.secret_string))) == jsonencode({ token = "" })
    error_message = "sms gateway secret placeholder"
  }
  # T25: Stripe în mod test; chei goale până le pune Zoltan cu scripts/set-stripe-keys.sh.
  assert {
    condition     = aws_secretsmanager_secret.stripe.name == "aradex/stripe" && aws_secretsmanager_secret.stripe.recovery_window_in_days == 0
    error_message = "stripe secret"
  }
  assert {
    condition     = jsonencode(sort(keys(jsondecode(nonsensitive(aws_secretsmanager_secret_version.stripe.secret_string))))) == jsonencode(["publishable_key", "secret_key", "webhook_secret"])
    error_message = "stripe secret placeholder keys"
  }
  assert {
    condition     = aws_secretsmanager_secret.jwt.recovery_window_in_days == 0 && aws_secretsmanager_secret.anthropic.recovery_window_in_days == 0
    error_message = "immediate secret deletion"
  }
  assert {
    condition     = output.db_secret_arn == "arn:aws:secretsmanager:eu-north-1:712710404828:secret:rds!db-mock"
    error_message = "db secret output comes from RDS-managed secret"
  }
}
