# Complete Deployment Guide

Step-by-step guide to deploy the email attachments infrastructure from scratch.

## Prerequisites Checklist

- [ ] AWS CLI installed and configured (`aws configure`)
- [ ] Terraform v1.6+ installed (`terraform --version`)
- [ ] Docker installed and running (`docker --version`)
- [ ] OpenSSL installed (`openssl version`)
- [ ] jq installed (optional, for JSON parsing)

## Deployment Steps

### 1. Clone and Configure

```bash
cd /path/to/email-attachments-infrastructure

# Copy example variables
cp terraform.tfvars.example terraform.tfvars

# Edit with your values (optional - defaults work fine)
nano terraform.tfvars
```

### 2. Generate CloudFront Keys

```bash
# Make script executable
chmod +x scripts/generate_keys.sh

# Generate RSA key pair
./scripts/generate_keys.sh
```

**Output:**
- `keys/private_key.pem` - CloudFront private key (2048-bit RSA)
- `keys/public_key.pem` - CloudFront public key

⚠️ **Never commit keys/ directory to Git!**

### 3. Build Lambda Package

```bash
# Make script executable
chmod +x scripts/build_lambda_docker.sh

# Build dependencies for Lambda (Amazon Linux 2)
./scripts/build_lambda_docker.sh
```

This uses Docker to compile `cryptography` for the correct platform.

**What happens:**
- Creates `lambda_build/` directory
- Installs `cryptography==41.0.7` (compiled for manylinux)
- Installs `cffi`, `pycparser`, and dependencies
- Copies Python code files

**Verify:**
```bash
ls lambda_build/ | grep cryptography
du -sh lambda_build/  # Should be ~20-25 MB
```

### 4. Initialize Terraform

```bash
terraform init
```

**What happens:**
- Downloads AWS provider (~5.0)
- Downloads archive provider (~2.4)
- Creates `.terraform/` directory

### 5. Review Plan

```bash
terraform plan
```

**Resources to be created (~30):**
- 1 S3 bucket (attachments)
- 1 CloudFront distribution + OAC + public key + key group
- 2 DynamoDB tables (EmailAttachments, UserEmailAccess)
- 1 Lambda function + IAM role + CloudWatch log group
- 1 Cognito User Pool + Client + Domain
- 1 API Gateway + Stage + Authorizer + Methods
- 1 Secrets Manager secret
- 3 CloudWatch alarms
- Supporting IAM roles and policies

### 6. Deploy Infrastructure

```bash
terraform apply
```

Type `yes` when prompted.

**Duration:** ~10-15 minutes

**What happens:**
- Creates all AWS resources
- Packages and uploads Lambda function
- Sets up API Gateway with Cognito authorizer
- Configures CloudFront with key group

**Note:** CloudFront distribution creation takes the longest (~10 min).

### 7. Post-Deployment Setup

```bash
# Make script executable
chmod +x scripts/setup.sh

# Run setup
./scripts/setup.sh
```

**What happens:**
1. Uploads CloudFront private key to Secrets Manager
2. Creates test users:
   - `testuser@example.com` (password: TestPass123!)
   - `recipient@example.com` (password: TestPass123!)
3. Uploads sample file: `emails/test-msg-001/test-document.pdf`
4. Populates DynamoDB:
   - EmailAttachments table with test email metadata
   - UserEmailAccess table with user permissions

**Verify:**
```bash
# Check users
aws cognito-idp admin-get-user \
  --user-pool-id $(terraform output -raw cognito_user_pool_id) \
  --username testuser@example.com

# Check DynamoDB
aws dynamodb scan --table-name UserEmailAccess --output table
aws dynamodb scan --table-name EmailAttachments --output table

# Check S3
aws s3 ls s3://$(terraform output -raw s3_bucket_name)/emails/test-msg-001/
```

## Testing the Deployment

### Quick Test

```bash
# Get configuration
CLIENT_ID=$(terraform output -raw cognito_client_id)
API_URL=$(terraform output -raw api_gateway_url)

# Authenticate
JWT_TOKEN=$(aws cognito-idp initiate-auth \
  --auth-flow USER_PASSWORD_AUTH \
  --client-id $CLIENT_ID \
  --auth-parameters USERNAME=testuser@example.com,PASSWORD=TestPass123! \
  --query 'AuthenticationResult.IdToken' \
  --output text)

# Generate signed URL
curl -X POST $API_URL \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"operation":"generate_url","s3_key":"emails/test-msg-001/test-document.pdf"}' \
  | jq .
```

### Expected Success Response

```json
{
  "signed_url": "https://d123abc.cloudfront.net/emails/test-msg-001/test-document.pdf?Expires=1738502400&Signature=ABC...&Key-Pair-Id=K2...",
  "expires_at": "2026-03-08T12:00:00Z",
  "s3_key": "emails/test-msg-001/test-document.pdf"
}
```

### Download the File

```bash
# Extract and download
SIGNED_URL=$(curl -s -X POST $API_URL \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"operation":"generate_url","s3_key":"emails/test-msg-001/test-document.pdf"}' \
  | jq -r '.signed_url')

curl "$SIGNED_URL" -o test-download.pdf
cat test-download.pdf
```

## Troubleshooting

### Issue: "No module named 'cryptography'"

**Cause:** Lambda dependencies not built or not uploaded.

**Fix:**
```bash
# Rebuild Lambda package
./scripts/build_lambda_docker.sh

# Verify
ls lambda_build/ | grep cryptography

# Redeploy
terraform apply
```

### Issue: "Access denied"

**Cause:** User not authorized for the file in DynamoDB.

**Fix:**
```bash
# Re-run setup to populate data
./scripts/setup.sh

# Verify user sub matches DynamoDB
USER_SUB=$(aws cognito-idp admin-get-user \
  --user-pool-id $(terraform output -raw cognito_user_pool_id) \
  --username testuser@example.com \
  --query 'UserAttributes[?Name==`sub`].Value' \
  --output text)

aws dynamodb scan --table-name UserEmailAccess \
  --filter-expression "user_id = :sub" \
  --expression-attribute-values "{\":sub\":{\"S\":\"$USER_SUB\"}}"
```

### Issue: "Incorrect username or password"

**Cause:** Using wrong username format.

**Fix:** Always use **email address** as username:
```bash
# ✅ Correct
USERNAME=testuser@example.com,PASSWORD=TestPass123!

# ❌ Wrong
USERNAME=testuser,PASSWORD=TestPass123!
```

### Issue: Docker build fails

**Cause:** Docker not running or not accessible.

**Fix:**
```bash
# Check Docker
docker info

# Start Docker Desktop (Windows/Mac)
# OR install Docker (Linux):
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
```

### Issue: CloudFront 403 Forbidden

**Cause:** CloudFront key group not properly configured or URL expired.

**Fix:**
1. Check key group in CloudFront console (should be configured by Terraform)
2. Verify signed URL hasn't expired
3. Check Lambda has correct KEY_PAIR_ID:
```bash
aws lambda get-function-configuration \
  --function-name $(terraform output -raw lambda_function_name) \
  --query 'Environment.Variables.KEY_PAIR_ID'

# Should match:
terraform output -raw cloudfront_public_key_id
```

## Viewing Logs

### Lambda Logs

```bash
# Tail logs in real-time
aws logs tail /aws/lambda/$(terraform output -raw lambda_function_name) --follow

# View recent errors
aws logs filter-log-events \
  --log-group-name /aws/lambda/$(terraform output -raw lambda_function_name) \
  --start-time $(date -u -d '10 minutes ago' +%s)000 \
  --filter-pattern "ERROR"
```

### API Gateway Logs

```bash
aws logs tail /aws/apigateway/email-app-prod --follow
```

## Outputs Reference

```bash
# View all outputs
terraform output

# Specific outputs
terraform output api_gateway_url
terraform output cloudfront_domain
terraform output cognito_user_pool_id
terraform output cognito_client_id
terraform output lambda_function_name
terraform output s3_bucket_name
```

## Cleanup

To destroy all resources:

```bash
# 1. Empty S3 bucket first
BUCKET_NAME=$(terraform output -raw s3_bucket_name)
aws s3 rm s3://$BUCKET_NAME --recursive

# 2. Destroy infrastructure
terraform destroy

# Type 'yes' when prompted
```

**Note:** Destroying takes ~10-15 minutes (CloudFront distribution deletion is slow).

## Next Steps

1. **Integrate with your email app:**
   - Replace test data with real email metadata
   - Add your user IDs to DynamoDB
   - Update Lambda to work with your authentication

2. **Production optimizations:**
   - Review `README_COST.md` for cost optimization strategies
   - Consider switching to ECDSA keys (faster)
   - Add ElastiCache Redis for authorization caching (at scale)
   - Enable CloudFront logging for analytics

3. **Security hardening:**
   - Rotate CloudFront keys regularly
   - Set up AWS CloudTrail for audit logging
   - Configure AWS WAF for API Gateway
   - Enable MFA for Cognito users

4. **Monitoring:**
   - Set up SNS topics for CloudWatch alarms
   - Configure AWS Cost Anomaly Detection
   - Enable AWS X-Ray for distributed tracing

## Support

For issues or questions:
- Check CloudWatch Logs for errors
- Review `README.md` for detailed documentation
- See `README_COST.md` for cost analysis and scaling

## Summary

✅ **You should now have:**
- Working CloudFront distribution with signed URLs
- Lambda function generating secure access links
- Cognito authentication with JWT tokens
- DynamoDB-based authorization
- API Gateway with proper security
- Test users and data ready to use

🎉 **Total deployment time:** ~20-30 minutes
