output "function_url" {
  value = module.server_function.lambda_function_url
}

output "domain_name" {
  value = aws_cloudfront_distribution.cdn.domain_name
}

output "http_domain_name" {
  value = "https://${var.project_domain}"
}
