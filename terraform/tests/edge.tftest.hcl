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
}

mock_provider "aws" {
  alias = "us_east_1"
}

variables {
  domain_name  = "aradex.example"
  alb_dns_name = "aradex-api-123.eu-north-1.elb.amazonaws.com"
  alb_zone_id  = "Z23TAZ7ZKVBDVR"
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
}
