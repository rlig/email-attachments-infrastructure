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

# Next steps after deployment
output "next_steps" {
  description = "Post-deployment setup instructions"
  value = <<-EOT

    ========================================
    🎉 Infrastructure Deployment Complete!
    ========================================

    NEXT STEPS:
    
    1. Run the post-deployment setup script:
       
       chmod +x scripts/setup.sh
       ./scripts/setup.sh
       
       This will:
       - Upload CloudFront private key to Secrets Manager
       - Create test users (testuser@example.com, recipient@example.com)
       - Upload sample attachment to S3
       - Populate DynamoDB with test data

    2. Test your deployment:
       
       # Get JWT token
       JWT_TOKEN=$(aws cognito-idp initiate-auth \
         --auth-flow USER_PASSWORD_AUTH \
         --client-id ${aws_cognito_user_pool_client.main.id} \
         --auth-parameters USERNAME=testuser@example.com,PASSWORD=TestPass123! \
         --query 'AuthenticationResult.IdToken' \
         --output text)
       
       # Generate signed URL
       curl -X POST ${aws_api_gateway_stage.prod.invoke_url}/generate-url \
         -H "Authorization: Bearer $JWT_TOKEN" \
         -H "Content-Type: application/json" \
         -d '{"operation":"generate_url","s3_key":"emails/test-msg-001/test-document.pdf"}' | jq .
       
       # Open the signed_url from the response in your browser to download the file

    3. View your resources:
       
       API Gateway URL: ${aws_api_gateway_stage.prod.invoke_url}/generate-url
       CloudFront Domain: ${aws_cloudfront_distribution.attachments.domain_name}
       S3 Bucket: ${aws_s3_bucket.attachments.id}
       Cognito User Pool: ${aws_cognito_user_pool.main.id}

    See README.md for complete documentation.
    
  EOT
}
