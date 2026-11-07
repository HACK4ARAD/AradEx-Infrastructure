mock_provider "aws" {
  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      arn            = "arn:aws:cloudfront::712710404828:distribution/EMOCK123"
      id             = "EMOCK123"
      domain_name    = "dmock.cloudfront.net"
      hosted_zone_id = "Z2FDTNDATAQYW2"
    }
  }
  mock_resource "aws_cloudfront_function" {
    defaults = { arn = "arn:aws:cloudfront::712710404828:function/aradex-spa-rewrite" }
  }
  mock_resource "aws_s3_bucket" {
    defaults = { arn = "arn:aws:s3:::aradex-site-mock", bucket = "aradex-site-mock", bucket_regional_domain_name = "aradex-site-mock.s3.eu-north-1.amazonaws.com" }
  }
  mock_resource "aws_cloudfront_vpc_origin" {
    defaults = { id = "vo_mock", arn = "arn:aws:cloudfront::712710404828:vpcorigin/vo_mock" }
  }
}

# Certificatul trebuie creat cu provider-ul din us-east-1: doar mock-ul ăsta produce ARN-uri us-east-1.
mock_provider "aws" {
  alias = "us_east_1"
  mock_resource "aws_acm_certificate" {
    defaults = {
      arn = "arn:aws:acm:us-east-1:712710404828:certificate/mock"
      domain_validation_options = [
        { domain_name = "aradex.example", resource_record_name = "_a.aradex.example.", resource_record_type = "CNAME", resource_record_value = "_x.acm-validations.aws." },
        { domain_name = "www.aradex.example", resource_record_name = "_b.www.aradex.example.", resource_record_type = "CNAME", resource_record_value = "_y.acm-validations.aws." },
      ]
    }
  }
  mock_resource "aws_acm_certificate_validation" {
    defaults = { certificate_arn = "arn:aws:acm:us-east-1:712710404828:certificate/mock" }
  }
}

variables {
  domain_name  = "aradex.example"
  alb_arn      = "arn:aws:elasticloadbalancing:eu-north-1:712710404828:loadbalancer/app/aradex-api/0123456789abcdef"
  alb_dns_name = "internal-aradex-api-123.eu-north-1.elb.amazonaws.com"
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
    condition     = aws_acm_certificate.this.domain_name == "aradex.example" && aws_acm_certificate.this.subject_alternative_names == toset(["www.aradex.example"]) && aws_acm_certificate.this.validation_method == "DNS"
    error_message = "cert apex + www, DNS validated"
  }
  assert {
    condition     = length(aws_route53_record.cert_validation) == 2
    error_message = "one validation record per domain"
  }
  assert {
    condition     = aws_route53_zone.this.name == "aradex.example"
    error_message = "zone"
  }
  assert {
    condition     = aws_s3_bucket_public_access_block.site.block_public_acls && aws_s3_bucket_public_access_block.site.block_public_policy && aws_s3_bucket_public_access_block.site.ignore_public_acls && aws_s3_bucket_public_access_block.site.restrict_public_buckets
    error_message = "bucket private"
  }
  assert {
    condition     = aws_s3_bucket.site.force_destroy && aws_cloudfront_origin_access_control.s3.signing_behavior == "always" && aws_cloudfront_origin_access_control.s3.origin_access_control_origin_type == "s3"
    error_message = "bucket force_destroy + OAC"
  }
  assert {
    condition = (
      jsondecode(aws_s3_bucket_policy.site.policy).Statement[0].Principal.Service == "cloudfront.amazonaws.com" &&
      jsondecode(aws_s3_bucket_policy.site.policy).Statement[0].Action == "s3:GetObject" &&
      jsondecode(aws_s3_bucket_policy.site.policy).Statement[0].Condition.StringEquals["AWS:SourceArn"] == "arn:aws:cloudfront::712710404828:distribution/EMOCK123"
    )
    error_message = "bucket readable only by this distribution"
  }
  # Review Focus 1: fără custom_error_response, altfel erorile API devin HTML.
  assert {
    condition     = length(aws_cloudfront_distribution.this.custom_error_response) == 0
    error_message = "no distribution-level error responses"
  }
  assert {
    condition = (
      aws_cloudfront_distribution.this.default_cache_behavior[0].viewer_protocol_policy == "redirect-to-https" &&
      aws_cloudfront_distribution.this.default_cache_behavior[0].compress &&
      aws_cloudfront_distribution.this.default_cache_behavior[0].cache_policy_id == "658327ea-f89d-4fab-a63d-7e88639e58f6" &&
      one(aws_cloudfront_distribution.this.default_cache_behavior[0].function_association).event_type == "viewer-request"
    )
    error_message = "default behavior: https, compress, CachingOptimized, spa rewrite"
  }
  assert {
    condition     = tolist([for b in aws_cloudfront_distribution.this.ordered_cache_behavior : b.path_pattern]) == tolist(["/api/*", "/swagger-ui*", "/v3/api-docs*"])
    error_message = "api path patterns"
  }
  # Review Focus 2: Authorization, query, body, toate metodele; fără rescriere SPA.
  assert {
    condition = alltrue([for b in aws_cloudfront_distribution.this.ordered_cache_behavior :
      b.cache_policy_id == "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" &&
      b.origin_request_policy_id == "b689b0a8-53d0-40ab-baf2-68738e2966ac" &&
      length(b.allowed_methods) == 7 &&
      length(b.function_association) == 0 &&
      b.target_origin_id == "api" &&
    b.viewer_protocol_policy == "redirect-to-https"])
    error_message = "api behaviors: no cache, all viewer headers, 7 methods, no function"
  }
  assert {
    condition = (
      aws_cloudfront_vpc_origin.api.vpc_origin_endpoint_config[0].origin_protocol_policy == "http-only" &&
      aws_cloudfront_vpc_origin.api.vpc_origin_endpoint_config[0].http_port == 80 &&
      aws_cloudfront_vpc_origin.api.vpc_origin_endpoint_config[0].arn == var.alb_arn
    )
    error_message = "vpc origin to internal alb over http"
  }
  assert {
    condition = (
      aws_cloudfront_distribution.this.aliases == toset(["aradex.example", "www.aradex.example"]) &&
      aws_cloudfront_distribution.this.default_root_object == "index.html" &&
      aws_cloudfront_distribution.this.http_version == "http2and3" &&
      aws_cloudfront_distribution.this.viewer_certificate[0].ssl_support_method == "sni-only" &&
      aws_cloudfront_distribution.this.viewer_certificate[0].minimum_protocol_version == "TLSv1.2_2021"
    )
    error_message = "distribution aliases, root object, http version, tls"
  }
  assert {
    condition     = startswith(aws_cloudfront_distribution.this.viewer_certificate[0].acm_certificate_arn, "arn:aws:acm:us-east-1:")
    error_message = "certificate comes from us-east-1"
  }
  assert {
    condition     = aws_cloudfront_function.spa.runtime == "cloudfront-js-2.0" && aws_cloudfront_function.spa.publish
    error_message = "spa function"
  }
  assert {
    condition = (
      length(aws_route53_record.site) == 4 &&
      toset([for r in aws_route53_record.site : "${r.name}/${r.type}"]) == toset(["aradex.example/A", "aradex.example/AAAA", "www.aradex.example/A", "www.aradex.example/AAAA"]) &&
      alltrue([for r in aws_route53_record.site : one(r.alias).name == "dmock.cloudfront.net"])
    )
    error_message = "A/AAAA alias records for apex and www"
  }
  assert {
    condition     = output.site_url == "https://aradex.example"
    error_message = "site url"
  }
}
