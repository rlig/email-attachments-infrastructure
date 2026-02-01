output "s3_bucket_name" {
  description = "S3 bucket name for attachments"
  value       = aws_s3_bucket.attachments.id
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.attachments.arn
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.attachments.id
}

output "cloudfront_domain" {
  description = "CloudFront domain name"
  value       = aws_cloudfront_distribution.attachments.domain_name
}

output "cloudfront_key_group_id" {
  description = "CloudFront key group ID"
  value       = aws_cloudfront_key_group.signing.id
}

output "cloudfront_public_key_id" {
  description = "CloudFront public key ID"
  value       = aws_cloudfront_public_key.signing_key.id
}

output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.main.id
}

output "cognito_user_pool_arn" {
  description = "Cognito User Pool ARN"
  value       = aws_cognito_user_pool.main.arn
}

output "cognito_client_id" {
  description = "Cognito User Pool Client ID"
  value       = aws_cognito_user_pool_client.main.id
}

# Note: Client secret is disabled (generate_secret = false) for public clients
# Uncomment if you need a confidential client with secret
# output "cognito_client_secret" {
#   description = "Cognito User Pool Client Secret"
#   value       = aws_cognito_user_pool_client.main.client_secret
#   sensitive   = true
# }

output "api_gateway_url" {
  description = "API Gateway invoke URL"
  value       = "${aws_api_gateway_stage.prod.invoke_url}/generate-url"
}

output "api_gateway_id" {
  description = "API Gateway REST API ID"
  value       = aws_api_gateway_rest_api.main.id
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.generate_signed_url.function_name
}

output "lambda_function_arn" {
  description = "Lambda function ARN"
  value       = aws_lambda_function.generate_signed_url.arn
}

output "dynamodb_attachments_table" {
  description = "DynamoDB EmailAttachments table name"
  value       = aws_dynamodb_table.email_attachments.name
}

output "dynamodb_access_table" {
  description = "DynamoDB UserEmailAccess table name"
  value       = aws_dynamodb_table.user_email_access.name
}

output "secrets_manager_secret_name" {
  description = "Secrets Manager secret name for CloudFront private key"
  value       = aws_secretsmanager_secret.cloudfront_private_key.name
}

# Quick start commands
output "quick_start_commands" {
  description = "Quick start commands for testing"
  value = <<-EOT
    # 1. Create test user (username must be email):
    aws cognito-idp admin-create-user \
      --user-pool-id ${aws_cognito_user_pool.main.id} \
      --username test@example.com \
      --user-attributes Name=email,Value=test@example.com \
      --temporary-password TempPass123!

    # 2. Set permanent password:
    aws cognito-idp admin-set-user-password \
      --user-pool-id ${aws_cognito_user_pool.main.id} \
      --username test@example.com \
      --password SecurePass123! \
      --permanent

    # 3. Get JWT token:
    aws cognito-idp initiate-auth \
      --auth-flow USER_PASSWORD_AUTH \
      --client-id ${aws_cognito_user_pool_client.main.id} \
      --auth-parameters USERNAME=test@example.com,PASSWORD=SecurePass123!

    # 4. Test API:
    curl -X POST ${aws_api_gateway_stage.prod.invoke_url}/generate-url \
      -H "Authorization: Bearer YOUR_JWT_TOKEN" \
      -H "Content-Type: application/json" \
      -d '{"operation":"generate_url","s3_key":"emails/test/file.pdf"}'
  EOT
}
