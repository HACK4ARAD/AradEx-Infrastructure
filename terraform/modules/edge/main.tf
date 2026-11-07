# Un singur domeniu: / -> S3 (PWA), /api/* -> ALB intern prin VPC origin. HTTPS cu certificat ACM din us-east-1.

locals {
  www = "www.${var.domain_name}"

  # Politici gestionate de AWS (ID-uri fixe, globale).
  cache_optimized               = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  cache_disabled                = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
  all_viewer_except_host_header = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
  api_path_patterns             = ["/api/*", "/swagger-ui*", "/v3/api-docs*"]
}

# --- DNS + certificat ------------------------------------------------------

resource "aws_route53_zone" "this" {
  name          = var.domain_name
  force_destroy = true
}

resource "aws_acm_certificate" "this" {
  provider                  = aws.us_east_1
  domain_name               = var.domain_name
  subject_alternative_names = [local.www]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# Cheile vin din domeniile cunoscute (nu din atributul calculat), ca for_each să fie cunoscut la plan.
locals {
  cert_validation = { for o in aws_acm_certificate.this.domain_validation_options : o.domain_name => o }
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

resource "aws_acm_certificate_validation" "this" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

# --- S3 (fișierele PWA) ----------------------------------------------------

resource "aws_s3_bucket" "site" {
  bucket_prefix = "aradex-site-"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "aradex-site"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "CloudFrontOnly"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.site.arn}/*"
      Condition = { StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.this.arn } }
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.site]
}

# --- CloudFront ------------------------------------------------------------

resource "aws_cloudfront_function" "spa" {
  name    = "aradex-spa-rewrite"
  runtime = "cloudfront-js-2.0"
  comment = "www -> apex; rutele SPA -> /index.html (doar comportamentul default)"
  code    = file("${path.module}/functions/spa-rewrite.js")
  publish = true
}

resource "aws_cloudfront_vpc_origin" "api" {
  vpc_origin_endpoint_config {
    name                   = "aradex-api"
    arn                    = var.alb_arn
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "http-only"

    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  comment             = "AradExperience"
  aliases             = [var.domain_name, local.www]
  default_root_object = "index.html"
  http_version        = "http2and3"
  is_ipv6_enabled     = true
  price_class         = "PriceClass_100"

  origin {
    origin_id                = "s3"
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
  }

  origin {
    origin_id   = "api"
    domain_name = var.alb_dns_name

    vpc_origin_config {
      vpc_origin_id            = aws_cloudfront_vpc_origin.api.id
      origin_keepalive_timeout = 5
      origin_read_timeout      = 30
    }
  }

  default_cache_behavior {
    target_origin_id       = "s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = local.cache_optimized

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.spa.arn
    }
  }

  # API + Swagger: fără cache, toate header-ele (inclusiv Authorization), query și body; fără rescriere SPA.
  dynamic "ordered_cache_behavior" {
    for_each = local.api_path_patterns
    content {
      path_pattern             = ordered_cache_behavior.value
      target_origin_id         = "api"
      viewer_protocol_policy   = "redirect-to-https"
      allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
      cached_methods           = ["GET", "HEAD"]
      compress                 = true
      cache_policy_id          = local.cache_disabled
      origin_request_policy_id = local.all_viewer_except_host_header
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.this.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

resource "aws_route53_record" "site" {
  for_each = {
    "apex-A"    = { name = var.domain_name, type = "A" }
    "apex-AAAA" = { name = var.domain_name, type = "AAAA" }
    "www-A"     = { name = local.www, type = "A" }
    "www-AAAA"  = { name = local.www, type = "AAAA" }
  }
  zone_id = aws_route53_zone.this.zone_id
  name    = each.value.name
  type    = each.value.type

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}
