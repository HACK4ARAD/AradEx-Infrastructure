mock_provider "aws" {
  mock_resource "aws_acm_certificate" {
    defaults = {
      arn = "arn:aws:acm:eu-north-1:712710404828:certificate/mock"
      domain_validation_options = [
        { domain_name = "aradex.example", resource_record_name = "_a.aradex.example.", resource_record_type = "CNAME", resource_record_value = "_x.acm-validations.aws." },
        { domain_name = "www.aradex.example", resource_record_name = "_b.www.aradex.example.", resource_record_type = "CNAME", resource_record_value = "_y.acm-validations.aws." },
      ]
    }
  }
  mock_resource "aws_acm_certificate_validation" {
    defaults = { certificate_arn = "arn:aws:acm:eu-north-1:712710404828:certificate/mock" }
  }
  # Tokenurile DKIM sunt un bloc calculat: mock-ul nu le generează, le dăm explicit.
  override_resource {
    target = aws_sesv2_email_identity.domain
    values = {
      arn = "arn:aws:ses:eu-north-1:712710404828:identity/aradex.example"
      dkim_signing_attributes = {
        current_signing_key_length    = "RSA_2048_BIT"
        domain_signing_private_key    = null
        domain_signing_selector       = null
        last_key_generation_timestamp = "2026-11-09T12:00:00Z"
        next_signing_key_length       = "RSA_2048_BIT"
        signing_attributes_origin     = "AWS_SES"
        status                        = "PENDING"
        tokens                        = ["tok1", "tok2", "tok3"]
      }
    }
  }
}

mock_provider "aws" {
  alias = "us_east_1"
}

variables {
  domain_name              = "aradex.example"
  alb_dns_name             = "aradex-api-123.eu-north-1.elb.amazonaws.com"
  alb_zone_id              = "Z23TAZ7ZKVBDVR"
  google_site_verification = "google-site-verification=test-token"
}

run "edge" {
  command = apply
  module {
    source = "./modules/edge"
  }
  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  assert {
    condition     = aws_route53_zone.this.name == "aradex.example"
    error_message = "zone"
  }
  # Certificatul e pentru ALB, deci în eu-north-1 (provider-ul implicit).
  assert {
    condition = (
      aws_acm_certificate.alb.domain_name == "aradex.example" &&
      aws_acm_certificate.alb.subject_alternative_names == toset(["www.aradex.example"]) &&
      aws_acm_certificate.alb.validation_method == "DNS" &&
      startswith(output.certificate_arn, "arn:aws:acm:eu-north-1:")
    )
    error_message = "regional cert for apex + www, DNS validated"
  }
  assert {
    condition     = length(aws_route53_record.cert_validation) == 2
    error_message = "one validation record per domain"
  }
  assert {
    condition = (
      length(aws_route53_record.site) == 2 &&
      toset([for r in aws_route53_record.site : "${r.name}/${r.type}"]) == toset(["aradex.example/A", "www.aradex.example/A"]) &&
      alltrue([for r in aws_route53_record.site : one(r.alias).name == var.alb_dns_name && one(r.alias).zone_id == var.alb_zone_id])
    )
    error_message = "A alias records for apex and www point to the ALB"
  }
  assert {
    condition     = output.site_url == "https://aradex.example"
    error_message = "site url"
  }
  # „Am uitat parola”: domeniul trimite emailuri prin SES, autentificate (DKIM, SPF pe MAIL FROM aliniat, DMARC)
  assert {
    condition     = aws_sesv2_email_identity.domain.email_identity == "aradex.example" && output.ses_identity_arn == "arn:aws:ses:eu-north-1:712710404828:identity/aradex.example"
    error_message = "SES domain identity"
  }
  assert {
    condition = (
      length(aws_route53_record.dkim) == 3 &&
      toset([for r in aws_route53_record.dkim : "${r.name}/${r.type}/${one(r.records)}"]) == toset([for t in ["tok1", "tok2", "tok3"] : "${t}._domainkey.aradex.example/CNAME/${t}.dkim.amazonses.com"])
    )
    error_message = "three Easy DKIM CNAMEs"
  }
  assert {
    condition = (
      aws_sesv2_email_identity_mail_from_attributes.domain.mail_from_domain == "mail.aradex.example" &&
      aws_sesv2_email_identity_mail_from_attributes.domain.behavior_on_mx_failure == "USE_DEFAULT_VALUE" &&
      aws_route53_record.mail_from_mx.name == "mail.aradex.example" && one(aws_route53_record.mail_from_mx.records) == "10 feedback-smtp.eu-north-1.amazonses.com" &&
      aws_route53_record.mail_from_spf.type == "TXT" && one(aws_route53_record.mail_from_spf.records) == "v=spf1 include:amazonses.com ~all"
    )
    error_message = "custom MAIL FROM with MX + SPF"
  }
  assert {
    condition     = aws_route53_record.dmarc.name == "_dmarc.aradex.example" && one(aws_route53_record.dmarc.records) == "v=DMARC1; p=none;"
    error_message = "DMARC record"
  }
  assert {
    condition     = one(aws_route53_record.google_site_verification).name == "aradex.example" && one(aws_route53_record.google_site_verification).type == "TXT" && one(one(aws_route53_record.google_site_verification).records) == "google-site-verification=test-token"
    error_message = "Google Search Console TXT on the apex"
  }
}
