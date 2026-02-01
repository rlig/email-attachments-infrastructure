# Email Attachments Infrastructure

Terraform infrastructure for secure, scalable email attachment delivery using AWS CloudFront, S3, Lambda, and Cognito.

## 🚀 Quick Start

```bash
# 1. Generate keys
./scripts/generate_keys.sh

# 2. Build Lambda package
./scripts/build_lambda_docker.sh

# 3. Deploy
terraform init
terraform apply

# 4. Setup test data
./scripts/setup.sh

# 5. Test
JWT_TOKEN=$(aws cognito-idp initiate-auth \
  --auth-flow USER_PASSWORD_AUTH \
  --client-id $(terraform output -raw cognito_client_id) \
  --auth-parameters USERNAME=testuser@example.com,PASSWORD=TestPass123! \
  --query 'AuthenticationResult.IdToken' --output text)

curl -X POST $(terraform output -raw api_gateway_url) \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"operation":"generate_url","s3_key":"emails/test-msg-001/test-document.pdf"}' | jq .
```

See [DEPLOYMENT.md](DEPLOYMENT.md) for complete step-by-step guide.

**Want to destroy and recreate?** See [DESTROY_AND_RECREATE.md](DESTROY_AND_RECREATE.md) - fully tested and automated!

## Architecture

- **S3**: Private bucket for attachment storage
- **CloudFront**: CDN with Origin Access Control (OAC) for secure delivery
- **Lambda**: Generates signed URLs/cookies with authorization
- **DynamoDB**: Stores email metadata and user access control
- **Cognito**: User authentication with email as username
- **API Gateway**: RESTful API with JWT authorization
- **Secrets Manager**: Stores CloudFront private key

## Prerequisites

1. **AWS CLI** configured with appropriate credentials
   ```bash
   aws configure
   ```

2. **Terraform** v1.6+ installed
   ```bash
   terraform --version
   ```

3. **Docker** for building Lambda dependencies
   ```bash
   docker --version
   ```

4. **OpenSSL** for key generation
   ```bash
   openssl version
   ```

5. **jq** for JSON processing (optional but recommended)
   ```bash
   jq --version
   ```

## Quick Start

### Step 1: Clone and Configure

```bash
# Clone repository
git clone <your-repo>
cd email-attachments-infrastructure

# Copy example variables
cp terraform.tfvars.example terraform.tfvars

# Edit variables with your values
nano terraform.tfvars
```

### Step 2: Generate CloudFront Keys

```bash
# Run key generation script
chmod +x scripts/generate_keys.sh
./scripts/generate_keys.sh

# This creates:
# - keys/private_key.pem (CloudFront private key)
# - keys/public_key.pem (CloudFront public key)
```

### Step 3: Build Lambda Package

**IMPORTANT:** Lambda requires platform-specific dependencies. The `cryptography` library has compiled C extensions that must be built for Amazon Linux 2.

**Option A: Using Docker (Recommended)**

```bash
# Build Lambda package using AWS Lambda Python image
chmod +x scripts/build_lambda_docker.sh
./scripts/build_lambda_docker.sh
```

This uses Docker to build dependencies on the correct platform (Amazon Linux 2).

**Option B: Using pip with platform flag (Alternative)**

```bash
# Install dependencies for Lambda's platform
pip install -r lambda/requirements.txt \
    --platform manylinux2014_x86_64 \
    --target lambda_build \
    --only-binary=:all: \
    --python-version 3.12

# Copy Python files
cp lambda/*.py lambda_build/
```

**What gets installed:**
- `cryptography` - For CloudFront URL signing (compiled for Linux)
- `boto3` - AWS SDK (already in Lambda, but included for completeness)

### Step 4: Initialize Terraform

```bash
terraform init
```

### Step 5: Review Plan

```bash
terraform plan
```

### Step 6: Deploy Infrastructure

```bash
terraform apply
```

This will create all resources (~10-15 minutes).

### Step 7: Post-Deployment Configuration

After Terraform completes, run the setup script to finalize configuration:

```bash
chmod +x scripts/setup.sh
./scripts/setup.sh
```

This script will:
1. Upload CloudFront private key to Secrets Manager
2. Create sample test users in Cognito (testuser@example.com, recipient@example.com)
3. Upload sample file to S3
4. Populate DynamoDB with test data and user access records

**Note:** The script is idempotent - safe to run multiple times.

## Quick Testing

After running `./scripts/setup.sh`, test your deployment:

```bash
# Get configuration
CLIENT_ID=$(terraform output -raw cognito_client_id)
API_URL=$(terraform output -raw api_gateway_url)

# Authenticate and get JWT token
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

# Expected output:
# {
#   "signed_url": "https://d123abc.cloudfront.net/emails/test-msg-001/test-document.pdf?Expires=...",
#   "expires_at": "2026-03-03T12:00:00Z",
#   "s3_key": "emails/test-msg-001/test-document.pdf"
# }

# Download the file
SIGNED_URL=$(curl -s -X POST $API_URL \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"operation":"generate_url","s3_key":"emails/test-msg-001/test-document.pdf"}' \
  | jq -r '.signed_url')

curl "$SIGNED_URL" -o test-download.pdf
cat test-download.pdf
```

## Detailed Testing Guide

### Test 1: Verify Setup

```bash
# Check if test users exist
USER_POOL_ID=$(terraform output -raw cognito_user_pool_id)
aws cognito-idp admin-get-user \
  --user-pool-id $USER_POOL_ID \
  --username testuser@example.com

# Check DynamoDB data
aws dynamodb scan --table-name UserEmailAccess --output table
aws dynamodb scan --table-name EmailAttachments --output table

# Check S3 file
BUCKET_NAME=$(terraform output -raw s3_bucket_name)
aws s3 ls s3://$BUCKET_NAME/emails/test-msg-001/
```

### Test 2: Authenticate

```bash
CLIENT_ID=$(terraform output -raw cognito_client_id)

# Get JWT token (valid for 1 hour)
JWT_TOKEN=$(aws cognito-idp initiate-auth \
  --auth-flow USER_PASSWORD_AUTH \
  --client-id $CLIENT_ID \
  --auth-parameters USERNAME=testuser@example.com,PASSWORD=TestPass123! \
  --query 'AuthenticationResult.IdToken' \
  --output text)

echo "Token: ${JWT_TOKEN:0:50}..."
```

### Test 3: Generate Signed URL

```bash
API_URL=$(terraform output -raw api_gateway_url)

# Generate signed URL for the test file
curl -X POST $API_URL \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"operation":"generate_url","s3_key":"emails/test-msg-001/test-document.pdf","expiration_days":7}' \
  | jq .
```

**Expected Response:**
```json
{
  "signed_url": "https://d123abc.cloudfront.net/emails/test-msg-001/test-document.pdf?Expires=1738502400&Signature=...",
  "expires_at": "2026-03-08T12:00:00Z",
  "s3_key": "emails/test-msg-001/test-document.pdf"
}
```

### Test 4: Access File via CloudFront

```bash
# Extract signed URL and download file
SIGNED_URL=$(curl -s -X POST $API_URL \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"operation":"generate_url","s3_key":"emails/test-msg-001/test-document.pdf"}' \
  | jq -r '.signed_url')

# Download file
curl "$SIGNED_URL" -o downloaded.pdf

# View content
cat downloaded.pdf
```

### Test 5: Generate Signed Cookies (Optional)

```bash
# Generate cookies for accessing all attachments in an email
curl -X POST $API_URL \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"operation":"generate_cookies","email_id":"test-msg-001","expiration_days":1}' \
  | jq .
```

### Test 6: Batch Generate URLs (Optional)

```bash
# Generate multiple signed URLs at once
curl -X POST $API_URL \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"operation":"batch_generate","s3_keys":["emails/test-msg-001/test-document.pdf"]}' \
  | jq .
```

## Configuration Variables

Edit `terraform.tfvars`:

```hcl
# Required
aws_region = "us-east-1"
project_name = "email-app"
environment = "prod"

# Optional - defaults provided
lambda_memory_size = 512
lambda_timeout = 30
dynamodb_billing_mode = "PAY_PER_REQUEST"
```

## Outputs

After deployment, important values are output:

```bash
# View all outputs
terraform output

# Specific outputs
terraform output api_gateway_url
terraform output cloudfront_domain
terraform output cognito_user_pool_id
```

## Costs

### Low Traffic (1M requests/month)
Estimated monthly costs for light usage:

- S3: $23 (1TB storage)
- CloudFront: $85 (1TB data transfer)
- Lambda: $20 (1M invocations)
- DynamoDB: $25 (on-demand)
- API Gateway: $35 (1M requests)
- Cognito: Free (up to 50k MAU)
- Secrets Manager: $0.40
- **Total: ~$188/month**

### Moderate Traffic (50 QPS / 130M requests/month)
Estimated monthly costs for moderate usage:

- CloudFront: $30,818 (648TB data transfer)
- Lambda: $235 (130M invocations)
- API Gateway: $454 (130M requests)
- CloudWatch: $409 (logs and monitoring)
- S3: $287 (10TB storage + requests)
- DynamoDB: $77 (on-demand)
- Cognito: Free (up to 50k MAU)
- Secrets Manager: $1
- **Total: ~$32,281/month** (~$387k/year)

**With optimizations:** ~$26,188/month (~$314k/year)

See `README_COST.md` for detailed cost analysis and optimization strategies.

## Scaling

### Current Architecture (50 QPS)
The baseline infrastructure handles 50 QPS efficiently without additional complexity.

### When to Optimize (100-200 QPS)
1. Switch to **ECDSA keys** (91% faster signing)
2. Implement **signed cookies** for multi-file access
3. Reduce **CloudWatch logging** to errors only

### High-Scale Optimizations (500+ QPS)
1. Add **ElastiCache Redis** for authorization caching
2. Enable **Lambda Provisioned Concurrency**
3. Use **DynamoDB DAX** for read caching
4. Contact AWS for **CloudFront Private Pricing Agreement**

See `README_COST.md` for complete scaling and cost optimization guide.

## Security

- S3 bucket is private (OAC only)
- All API calls require JWT authentication
- Authorization checked before generating URLs
- Signed URLs expire (configurable)
- CloudTrail enabled for audit logging
- Secrets encrypted at rest

## Troubleshooting

### CloudFront returns 403

- Verify OAC is properly configured in distribution
- Check S3 bucket policy includes CloudFront service principal
- Ensure key group is associated with distribution behavior

### Lambda authorization fails

- Verify DynamoDB tables populated with test data
- Check Lambda CloudWatch logs for errors
- Ensure Lambda has DynamoDB read permissions

### API Gateway returns 401

- Verify JWT token is valid and not expired
- Check Cognito authorizer configuration
- Ensure Authorization header format: `Bearer <token>`

### Signed URL doesn't work

- Verify CloudFront key pair ID matches Lambda environment variable
- Check private key in Secrets Manager is correct format
- Ensure URL hasn't expired

## Cleanup

To destroy all resources:

```bash
# Remove all data from S3 bucket first
BUCKET_NAME=$(terraform output -raw s3_bucket_name)
aws s3 rm s3://$BUCKET_NAME --recursive

# Destroy infrastructure
terraform destroy
```

See [DESTROY_AND_RECREATE.md](DESTROY_AND_RECREATE.md) for complete destroy/recreate guide.

## Documentation

- **[WORKFLOW_SUMMARY.md](WORKFLOW_SUMMARY.md)** - ⭐ START HERE: Complete workflow overview
- **[README.md](README.md)** - Main documentation (this file)
- **[DEPLOYMENT.md](DEPLOYMENT.md)** - Complete step-by-step deployment guide
- **[TESTING.md](TESTING.md)** - Testing commands and verification
- **[CHANGELOG.md](CHANGELOG.md)** - All issues fixed during development
- **[DESTROY_AND_RECREATE.md](DESTROY_AND_RECREATE.md)** - Destroy and recreate guide
- **[README_COST.md](README_COST.md)** - Cost analysis and optimization

## Production Ready

✅ **This infrastructure has been tested end-to-end:**
- All 7 deployment issues identified and fixed
- Destroy and recreate workflow verified
- Complete automation from scratch (20-30 minutes)
- Test data and scripts included
- Comprehensive documentation

🎉 **Ready to integrate with your email application!**

## Support

For issues or questions:
- Check CloudWatch Logs for Lambda errors
- Review API Gateway execution logs
- Enable CloudFront logging for request debugging
- See [CHANGELOG.md](CHANGELOG.md) for common errors and solutions

## License

MIT
