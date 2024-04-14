################################################
###### AWS region
################################################
data "aws_region" "current" {
  # Uses the default aws provider
}

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
  name         = var.project_domain
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
### Lambda and it's resources
################################################
resource "aws_s3_bucket" "s3_storage" {
  bucket = "${var.project_name}-${var.environment}-storage"
  tags   = local.tags
}

resource "aws_s3_bucket_public_access_block" "s3_public" {
  bucket                  = aws_s3_bucket.s3_storage.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_cors_configuration" "s3_cors" {
  bucket = aws_s3_bucket.s3_storage.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
  }
}

resource "aws_s3_bucket_ownership_controls" "example" {
  bucket = aws_s3_bucket.s3_storage.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

module "server_function" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "6.4.0"

  lambda_at_edge = false
  snap_start     = false

  function_name              = "${var.project_name}-${var.environment}-server-function"
  description                = "Server function"
  handler                    = "./server.js"
  runtime                    = "nodejs20.x"
  architectures              = ["arm64"]
  memory_size                = 512
  ephemeral_storage_size     = 512
  timeout                    = 30
  publish                    = true
  create_lambda_function_url = true
  create_package             = true
  store_on_s3                = false

  source_path = [
    {
      path             = "../.next/standalone"
      npm_requirements = false
      patterns = [
        # Exclude binaries for other platforms. This will exclude Prisma's binary
        "!.*/.*darwin.*\\.node"
      ]
    },
    {
      path          = "../public"
      prefix_in_zip = "public"
    },
    {
      path          = "../.next/static"
      prefix_in_zip = ".next/static"
    }
  ]

  artifacts_dir = ".terraform"

  create_role      = true
  role_description = "Server Lambda function role"

  invoke_mode = var.lambda_streaming ? "RESPONSE_STREAMING" : "BUFFERED"

  attach_cloudwatch_logs_policy     = true
  cloudwatch_logs_retention_in_days = 1

  environment_variables = merge(var.lambda_envs, {
    AWS_LAMBDA_EXEC_WRAPPER = "/opt/lambda-adapter/bootstrap" // Neccessary for Runtime API
    SERVER_URL              = var.healthcheck_url             // Adapter waits for this to be active
    USE_STREAM              = var.lambda_streaming ? "true" : "false"
    NEXT_SHARP_PATH         = "/opt/nodejs/node_modules/sharp"
  })

  layers = [
    "arn:aws:lambda:eu-central-1:801586546618:layer:NetworkAdapterLayer:30", // Network Adapter
    "arn:aws:lambda:eu-central-1:801586546618:layer:SharpLayer:3"            // Sharp layer
  ]

  tags = local.tags
}

################################################
### CloudFront function
################################################
resource "aws_cloudfront_function" "main" {
  name    = "${var.project_name}-${var.environment}-preserve-host"
  runtime = "cloudfront-js-1.0"
  comment = "Function for Preserving Original Host"
  publish = true
  code    = <<EOF
    function handler(event) {
      var request = event.request;
      request.headers["x-forwarded-host"] = request.headers.host;
      return request;
    }
  EOF
}

resource "aws_cloudfront_function" "redirect" {
  name    = "${var.project_name}-${var.environment}-redirect-to-www"
  runtime = "cloudfront-js-1.0"
  comment = "Function for Redirecting to www"
  publish = true
  code    = <<EOF
    function handler(event) {
      var request = event.request;
      var host = request.headers.host.value;
      var url = request.uri;
      if (host.includes("www.") && !host.includes("cloudfront")) {
        return request;
      }
      var redirectUrl = "https://www." + host + url;
      var response = {
        statusCode: 301,
        statusDescription: "Moved Permanently",
        headers: {
          location: {
            value: redirectUrl,
          },
        },
      };
      return response;
    }
  EOF
}

################################################
### Cache policies
################################################
data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

resource "aws_cloudfront_cache_policy" "assets_cache" {
  name = "${var.project_name}-${var.environment}-assets-caching-policy"

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_gzip   = true
    enable_accept_encoding_brotli = true

    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "all"
    }
  }
}

resource "aws_cloudfront_cache_policy" "server_cache" {
  name = "${var.project_name}-${var.environment}-server-cache"

  default_ttl = 0
  max_ttl     = 31536000
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true
    cookies_config {
      cookie_behavior = "all"
    }
    headers_config {
      header_behavior = "whitelist"
      headers {
        items = ["next-url", "rsc", "next-router-prefetch", "next-router-state-tree", "accept"]
      }
    }
    query_strings_config {
      query_string_behavior = "all"
    }
  }
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host_header" {
  name = "Managed-AllViewerExceptHostHeader"
}

################################################
### CloudFront distribution
################################################
resource "aws_cloudfront_distribution" "cdn" {
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

  ordered_cache_behavior {
    path_pattern             = "/api*"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD", "OPTIONS"]
    viewer_protocol_policy   = "redirect-to-https"
    target_origin_id         = module.server_function.lambda_function_name
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host_header.id
    compress                 = true

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.main.arn
    }
  }

  # Watch out! It wont work properly without origin_request_policy_id
  ordered_cache_behavior {
    path_pattern             = "/_next/data/*"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD", "OPTIONS"]
    viewer_protocol_policy   = "redirect-to-https"
    target_origin_id         = module.server_function.lambda_function_name
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host_header.id
    compress                 = true
  }

  ordered_cache_behavior {
    path_pattern           = "/_next/static/*"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD", "OPTIONS"]
    viewer_protocol_policy = "redirect-to-https"
    target_origin_id       = module.server_function.lambda_function_name
    cache_policy_id        = aws_cloudfront_cache_policy.assets_cache.id
    compress               = true
  }

  ordered_cache_behavior {
    path_pattern             = "/_next/image*"
    allowed_methods          = ["GET", "HEAD", "OPTIONS"]
    cached_methods           = ["GET", "HEAD", "OPTIONS"]
    viewer_protocol_policy   = "redirect-to-https"
    target_origin_id         = module.server_function.lambda_function_name
    cache_policy_id          = aws_cloudfront_cache_policy.assets_cache.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host_header.id
    compress                 = true
  }

  default_cache_behavior {
    allowed_methods          = ["GET", "HEAD", "OPTIONS"]
    cached_methods           = ["GET", "HEAD", "OPTIONS"]
    target_origin_id         = module.server_function.lambda_function_name
    viewer_protocol_policy   = "redirect-to-https"
    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host_header.id
    compress                 = true

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.redirect.arn
    }
  }

  viewer_certificate {
    acm_certificate_arn            = aws_acm_certificate.main.arn
    cloudfront_default_certificate = false
    minimum_protocol_version       = "TLSv1.2_2021"
    ssl_support_method             = "sni-only"
  }

  origin {
    domain_name         = "${module.server_function.lambda_function_url_id}.lambda-url.${aws_region.current.name}.on.aws"
    origin_id           = module.server_function.lambda_function_name
    connection_attempts = 3
    connection_timeout  = 10
    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "https-only"
      origin_ssl_protocols     = ["TLSv1.2"]
      origin_keepalive_timeout = 5
      origin_read_timeout      = 30
    }
  }

  tags = local.tags
}


#############################
### Route53 records
#############################

######################
### A record
######################
resource "aws_route53_record" "a_alias" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "www.${var.project_domain}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.cdn.domain_name
    zone_id                = aws_cloudfront_distribution.cdn.hosted_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "apex_a_alias" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.project_domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.cdn.domain_name
    zone_id                = aws_cloudfront_distribution.cdn.hosted_zone_id
    evaluate_target_health = true
  }
}

######################
### AAAA record
######################
resource "aws_route53_record" "aaaa_alias" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "www.${var.project_domain}"
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.cdn.domain_name
    zone_id                = aws_cloudfront_distribution.cdn.hosted_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "apex_aaaa_alias" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.project_domain
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.cdn.domain_name
    zone_id                = aws_cloudfront_distribution.cdn.hosted_zone_id
    evaluate_target_health = true
  }
}
