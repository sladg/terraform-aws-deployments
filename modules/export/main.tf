################################################
###### ACM
################################################
resource "aws_acm_certificate" "main" {
  provider                  = aws.virginia
  domain_name               = var.project_domain
  subject_alternative_names = ["www.${var.project_domain}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = local.tags
}

resource "aws_acm_certificate_validation" "main" {
  provider                = aws.virginia
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.main : record.fqdn]
}

data "aws_route53_zone" "main" {
  name         = local.zone_domain
  private_zone = false
}

#############################
###### Route53 record
#############################
resource "aws_route53_record" "main" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options : dvo.domain_name => {
      name    = dvo.resource_record_name
      record  = dvo.resource_record_value
      type    = dvo.resource_record_type
      zone_id = data.aws_route53_zone.main.zone_id
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = each.value.zone_id
}

################################################
### S3 bucket for static content
################################################
resource "aws_s3_bucket" "s3_storage" {
  bucket        = "${var.project_name}-${var.environment}-assets"
  force_destroy = true
  tags          = local.tags
}

resource "aws_s3_bucket_public_access_block" "s3_public" {
  bucket                  = aws_s3_bucket.s3_storage.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "example" {
  bucket = aws_s3_bucket.s3_storage.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_policy" "policy" {
  bucket = aws_s3_bucket.s3_storage.id

  policy = jsonencode({
    Version = "2008-10-17"
    Id      = "PolicyForCloudFrontPrivateContent"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.s3_storage.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.main.arn
          }
        }
      }
    ]
  })
}

################################################
### Cache policies
################################################
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

resource "aws_cloudfront_origin_access_control" "cloudfront_s3_oac" {
  name                              = "${var.project_name}-${var.environment}-oac-s3"
  description                       = "Cloud Front S3 OAC"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

################################################
### Lambda@Edge handling redirects to `index.html` in subfolders
################################################
resource "aws_cloudfront_function" "main" {
  name    = "${var.project_name}-${var.environment}-redirect-to-index"
  runtime = "cloudfront-js-1.0"
  comment = "Function for correctly point to index.html in subfolders"
  publish = true
  code    = <<EOF
    function handler(event) {
      var request = event.request;
      var uri = request.uri;

      // Check whether the URI is missing a file name.
      if (uri.endsWith('/')) {
          request.uri += 'index.html';
      }
      // Check whether the URI is missing a file extension.
      else if (!uri.includes('.')) {
          request.uri += '/index.html';
      }

      return request;
    }
  EOF
}


################################################
### CloudFront distribution
################################################
resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  aliases             = [var.project_domain, "www.${var.project_domain}"]
  is_ipv6_enabled     = true
  price_class         = "PriceClass_100"
  retain_on_delete    = false
  wait_for_deployment = true

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    target_origin_id       = "s3StaticSite"
    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
    compress               = true
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.main.arn
    }
  }

  viewer_certificate {
    acm_certificate_arn            = aws_acm_certificate.main.arn
    cloudfront_default_certificate = false
    minimum_protocol_version       = "TLSv1.2_2021"
    ssl_support_method             = "sni-only"
  }

  origin {
    domain_name              = aws_s3_bucket.s3_storage.bucket_regional_domain_name
    origin_id                = "s3StaticSite"
    origin_access_control_id = aws_cloudfront_origin_access_control.cloudfront_s3_oac.id
  }

  custom_error_response {
    error_code         = 404
    response_code      = 404
    response_page_path = "/404.html"
  }

  tags = local.tags
}

################################################
### Route53 records
################################################

################################################
### A record
################################################
resource "aws_route53_record" "a_alias" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "www.${var.project_domain}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "apex_a_alias" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.project_domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = true
  }
}

################################################
### AAAA record
################################################
resource "aws_route53_record" "aaaa_alias" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "www.${var.project_domain}"
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "apex_aaaa_alias" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.project_domain
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = true
  }
}

################################################
### Upload files to S3
################################################
resource "null_resource" "remove_and_upload_to_s3" {
  triggers = {
    always_run = timestamp()
  }
  depends_on = [aws_s3_bucket.s3_storage]
  provisioner "local-exec" {
    command = "aws s3 sync ${local.source_dir} s3://${aws_s3_bucket.s3_storage.id} --delete --quiet"
  }
}

################################################
### Invalidate CloudFront cache
################################################
resource "null_resource" "invalidate_cache" {
  triggers = {
    always_run = timestamp()
  }
  depends_on = [aws_cloudfront_distribution.main]
  count      = var.invalidate_on_deploy ? 1 : 0
  provisioner "local-exec" {
    command = "aws cloudfront create-invalidation --distribution-id ${aws_cloudfront_distribution.main.id} --paths '/*'"
  }
}
