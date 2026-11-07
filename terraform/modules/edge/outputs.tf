output "name_servers" {
  description = "Se pun la registrar."
  value       = aws_route53_zone.this.name_servers
}

output "bucket_name" {
  value = aws_s3_bucket.site.bucket
}

output "bucket_arn" {
  value = aws_s3_bucket.site.arn
}

output "distribution_id" {
  value = aws_cloudfront_distribution.this.id
}

output "distribution_arn" {
  value = aws_cloudfront_distribution.this.arn
}

output "site_url" {
  value = "https://${var.domain_name}"
}
