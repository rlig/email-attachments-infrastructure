# Secrets Manager for CloudFront private key
resource "aws_secretsmanager_secret" "cloudfront_private_key" {
  name                    = "cloudfront/${var.project_name}-private-key-${var.environment}"
  description             = "CloudFront private key for signing URLs"
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}-cloudfront-key"
  }
}

# Secret value will be populated by setup script after key generation
# This is a placeholder that gets updated post-deployment
resource "aws_secretsmanager_secret_version" "cloudfront_private_key" {
  secret_id     = aws_secretsmanager_secret.cloudfront_private_key.id
  secret_string = "PLACEHOLDER - Will be updated by setup script"

  lifecycle {
    ignore_changes = [secret_string]
  }
}
