output "bucket_name" {
  value = aws_s3_bucket.s3_storage.bucket
}

output "cloudfront_domain" {
  value       = aws_cloudfront_distribution.main.domain_name
  description = "The domain name of the CloudFront distribution"
}

output "apex_http_domain_name" {
  value       = "https://${var.project_domain}"
  description = "URL of the project"
}

output "https_domain_name" {
  value       = "https://www.${var.project_domain}"
  description = "URL of the project"
}
