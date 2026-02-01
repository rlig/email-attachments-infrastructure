# CloudFront Origin Access Control (OAC)
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "${var.project_name}-oac-${var.environment}"
  description                       = "OAC for ${var.project_name} S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "attachments" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.project_name} email attachments CDN"
  price_class         = var.cloudfront_price_class
  wait_for_deployment = false

  origin {
    domain_name              = aws_s3_bucket.attachments.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.attachments.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.attachments.id}"

    forwarded_values {
      query_string = false
      headers      = []

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 86400  # 1 day
    max_ttl                = 31536000 # 1 year
    compress               = true

    # Restrict viewer access - requires signed URLs/cookies
    trusted_key_groups = [aws_cloudfront_key_group.signing.id]
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  # Optional: Enable logging
  dynamic "logging_config" {
    for_each = var.enable_cloudfront_logging ? [1] : []
    content {
      include_cookies = false
      bucket          = aws_s3_bucket.cloudfront_logs[0].bucket_domain_name
      prefix          = "cloudfront/"
    }
  }

  tags = {
    Name = "${var.project_name}-distribution"
  }
}

# CloudFront Public Key (from generated key pair)
resource "aws_cloudfront_public_key" "signing_key" {
  name        = "${var.project_name}-signing-key-${var.environment}"
  encoded_key = file("${path.module}/keys/public_key.pem")
  comment     = "Public key for CloudFront signed URLs"
}

# CloudFront Key Group
resource "aws_cloudfront_key_group" "signing" {
  name    = "${var.project_name}-keygroup-${var.environment}"
  comment = "Key group for ${var.project_name} signed URLs"
  items   = [aws_cloudfront_public_key.signing_key.id]
}

# Optional: S3 bucket for CloudFront logs
resource "aws_s3_bucket" "cloudfront_logs" {
  count  = var.enable_cloudfront_logging ? 1 : 0
  bucket = "${var.project_name}-cloudfront-logs-${var.environment}-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name = "${var.project_name}-cloudfront-logs"
  }
}

resource "aws_s3_bucket_public_access_block" "cloudfront_logs" {
  count  = var.enable_cloudfront_logging ? 1 : 0
  bucket = aws_s3_bucket.cloudfront_logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "cloudfront_logs" {
  count  = var.enable_cloudfront_logging ? 1 : 0
  bucket = aws_s3_bucket.cloudfront_logs[0].id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}
