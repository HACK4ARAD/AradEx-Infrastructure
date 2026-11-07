# Domeniul: zona Route 53 (nameserverele sunt deja la registrar), certificatul ACM pentru ALB (eu-north-1)
# și înregistrările A alias spre ALB. Fără CloudFront: contul nu poate crea distribuții (verificare AWS Support).

locals {
  www = "www.${var.domain_name}"
}

resource "aws_route53_zone" "this" {
  name          = var.domain_name
  force_destroy = true
}

resource "aws_acm_certificate" "alb" {
  domain_name               = var.domain_name
  subject_alternative_names = [local.www]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# Cheile vin din domeniile cunoscute (nu din atributul calculat), ca for_each să fie cunoscut la plan.
locals {
  cert_validation = { for o in aws_acm_certificate.alb.domain_validation_options : o.domain_name => o }
}

resource "aws_route53_record" "cert_validation" {
  for_each        = toset([var.domain_name, local.www])
  zone_id         = aws_route53_zone.this.zone_id
  name            = local.cert_validation[each.key].resource_record_name
  type            = local.cert_validation[each.key].resource_record_type
  records         = [local.cert_validation[each.key].resource_record_value]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "alb" {
  certificate_arn         = aws_acm_certificate.alb.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

resource "aws_route53_record" "site" {
  for_each = { apex = var.domain_name, www = local.www }
  zone_id  = aws_route53_zone.this.zone_id
  name     = each.value
  type     = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = false
  }
}
