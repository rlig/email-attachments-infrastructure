# Testing Quick Reference

Quick commands for testing the deployed infrastructure.

## Prerequisites

Ensure you've completed:
```bash
./scripts/generate_keys.sh
./scripts/build_lambda_docker.sh
terraform apply
./scripts/setup.sh
```

## Test Users

| Username | Password | Role |
|----------|----------|------|
| testuser@example.com | TestPass123! | Sender |
| recipient@example.com | TestPass123! | Recipient |

## Quick Test Commands

### Get Configuration
```bash
export CLIENT_ID=$(terraform output -raw cognito_client_id)
export API_URL=$(terraform output -raw api_gateway_url)
export USER_POOL_ID=$(terraform output -raw cognito_user_pool_id)
export BUCKET_NAME=$(terraform output -raw s3_bucket_name)
```

### Authenticate
```bash
export JWT_TOKEN=$(aws cognito-idp initiate-auth \
  --auth-flow USER_PASSWORD_AUTH \
  --client-id $CLIENT_ID \
  --auth-parameters USERNAME=testuser@example.com,PASSWORD=TestPass123! \
  --query 'AuthenticationResult.IdToken' \
  --output text)

echo "Token: ${JWT_TOKEN:0:50}..."
```

### Generate Signed URL
```bash
curl -X POST $API_URL \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"operation":"generate_url","s3_key":"emails/test-msg-001/test-document.pdf"}' \
  | jq .
```

### Download File
```bash
SIGNED_URL=$(curl -s -X POST $API_URL \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"operation":"generate_url","s3_key":"emails/test-msg-001/test-document.pdf"}' \
  | jq -r '.signed_url')

curl "$SIGNED_URL" -o downloaded.pdf
cat downloaded.pdf
```

## All Operations

### 1. Generate Signed URL (Default)
```bash
curl -X POST $API_URL \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "operation": "generate_url",
    "s3_key": "emails/test-msg-001/test-document.pdf",
    "expiration_days": 7
  }' | jq .
```

**Response:**
```json
{
  "signed_url": "https://d123.cloudfront.net/...",
  "expires_at": "2026-03-08T12:00:00Z",
  "s3_key": "emails/test-msg-001/test-document.pdf"
}
```

### 2. Generate Signed Cookies
```bash
curl -X POST $API_URL \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "operation": "generate_cookies",
    "email_id": "test-msg-001",
    "expiration_days": 1
  }' | jq .
```

**Response:**
```json
{
  "CloudFront-Policy": "eyJTdGF0ZW1...",
  "CloudFront-Signature": "abc123...",
  "CloudFront-Key-Pair-Id": "K2...",
  "expires_at": "2026-02-02T12:00:00Z"
}
```

### 3. Batch Generate URLs
```bash
curl -X POST $API_URL \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "operation": "batch_generate",
    "s3_keys": [
      "emails/test-msg-001/test-document.pdf"
    ],
    "expiration_days": 7
  }' | jq .
```

**Response:**
```json
{
  "signed_urls": [
    {
      "signed_url": "https://...",
      "expires_at": "2026-03-08T12:00:00Z",
      "s3_key": "emails/test-msg-001/test-document.pdf"
    }
  ],
  "authorized_count": 1,
  "requested_count": 1
}
```

## Verification Commands

### Check Users
```bash
# List users
aws cognito-idp list-users \
  --user-pool-id $USER_POOL_ID \
  --query 'Users[*].[Username,UserStatus]' \
  --output table

# Get user details
aws cognito-idp admin-get-user \
  --user-pool-id $USER_POOL_ID \
  --username testuser@example.com
```

### Check DynamoDB
```bash
# UserEmailAccess table
aws dynamodb scan \
  --table-name UserEmailAccess \
  --output table

# EmailAttachments table
aws dynamodb scan \
  --table-name EmailAttachments \
  --output table
```

### Check S3
```bash
# List files
aws s3 ls s3://$BUCKET_NAME/emails/test-msg-001/

# Download directly (requires permissions)
aws s3 cp s3://$BUCKET_NAME/emails/test-msg-001/test-document.pdf ./local-copy.pdf
```

### Check Lambda Logs
```bash
# Tail recent logs
aws logs tail /aws/lambda/email-app-generate-url-prod --since 5m

# Filter errors
aws logs filter-log-events \
  --log-group-name /aws/lambda/email-app-generate-url-prod \
  --start-time $(date -u -d '10 minutes ago' +%s)000 \
  --filter-pattern "ERROR"
```

### Check CloudFront
```bash
# Get distribution details
DISTRIBUTION_ID=$(terraform output -raw cloudfront_distribution_id)
aws cloudfront get-distribution --id $DISTRIBUTION_ID

# Get distribution status
aws cloudfront get-distribution \
  --id $DISTRIBUTION_ID \
  --query 'Distribution.Status'
```

## Error Scenarios

### Test Invalid Token
```bash
curl -X POST $API_URL \
  -H "Authorization: Bearer invalid-token" \
  -H "Content-Type: application/json" \
  -d '{"operation":"generate_url","s3_key":"emails/test-msg-001/test-document.pdf"}'

# Expected: 401 Unauthorized
```

### Test Unauthorized File
```bash
curl -X POST $API_URL \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"operation":"generate_url","s3_key":"emails/unauthorized/file.pdf"}'

# Expected: {"error": "Access denied"}
```

### Test Missing Parameters
```bash
curl -X POST $API_URL \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"operation":"generate_url"}'

# Expected: {"error": "s3_key is required"}
```

### Test Invalid Operation
```bash
curl -X POST $API_URL \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"operation":"invalid_op","s3_key":"emails/test-msg-001/test-document.pdf"}'

# Expected: {"error": "Unknown operation: invalid_op"}
```

## Performance Testing

### Simple Load Test
```bash
# Run 100 requests
for i in {1..100}; do
  curl -s -X POST $API_URL \
    -H "Authorization: Bearer $JWT_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"operation":"generate_url","s3_key":"emails/test-msg-001/test-document.pdf"}' \
    &
done
wait

echo "100 requests completed"
```

### Monitor Lambda Performance
```bash
# Get Lambda metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Duration \
  --dimensions Name=FunctionName,Value=email-app-generate-url-prod \
  --start-time $(date -u -d '1 hour ago' --iso-8601=seconds) \
  --end-time $(date -u --iso-8601=seconds) \
  --period 300 \
  --statistics Average,Maximum
```

## Cleanup Test Data

### Reset Test User Password
```bash
aws cognito-idp admin-set-user-password \
  --user-pool-id $USER_POOL_ID \
  --username testuser@example.com \
  --password NewPass123! \
  --permanent
```

### Delete Test User
```bash
aws cognito-idp admin-delete-user \
  --user-pool-id $USER_POOL_ID \
  --username testuser@example.com
```

### Clear DynamoDB Tables
```bash
# Delete test data
aws dynamodb delete-item \
  --table-name UserEmailAccess \
  --key '{"user_id":{"S":"USER_SUB"},"email_id":{"S":"test-msg-001"}}'

aws dynamodb delete-item \
  --table-name EmailAttachments \
  --key '{"email_id":{"S":"test-msg-001"}}'
```

### Delete S3 Test File
```bash
aws s3 rm s3://$BUCKET_NAME/emails/test-msg-001/test-document.pdf
```

## Complete Test Script

Save as `test.sh`:

```bash
#!/bin/bash
set -e

echo "=== Email Attachments Infrastructure Test ==="
echo ""

# Configuration
export CLIENT_ID=$(terraform output -raw cognito_client_id)
export API_URL=$(terraform output -raw api_gateway_url)

echo "1. Authenticating..."
export JWT_TOKEN=$(aws cognito-idp initiate-auth \
  --auth-flow USER_PASSWORD_AUTH \
  --client-id $CLIENT_ID \
  --auth-parameters USERNAME=testuser@example.com,PASSWORD=TestPass123! \
  --query 'AuthenticationResult.IdToken' \
  --output text)
echo "✓ Authenticated"

echo ""
echo "2. Generating signed URL..."
RESPONSE=$(curl -s -X POST $API_URL \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"operation":"generate_url","s3_key":"emails/test-msg-001/test-document.pdf"}')

echo "$RESPONSE" | jq .

SIGNED_URL=$(echo "$RESPONSE" | jq -r '.signed_url')

if [ "$SIGNED_URL" = "null" ]; then
  echo "❌ Failed to generate signed URL"
  exit 1
fi

echo "✓ Signed URL generated"

echo ""
echo "3. Downloading file..."
curl -s "$SIGNED_URL" -o test-download.pdf

if [ -f test-download.pdf ]; then
  echo "✓ File downloaded"
  echo "Content:"
  cat test-download.pdf
  rm test-download.pdf
else
  echo "❌ Failed to download file"
  exit 1
fi

echo ""
echo "=== All tests passed! ==="
```

Run with:
```bash
chmod +x test.sh
./test.sh
```

## Monitoring Dashboard

### Create CloudWatch Dashboard
```bash
aws cloudwatch put-dashboard \
  --dashboard-name EmailAttachmentsInfra \
  --dashboard-body file://dashboard.json
```

**dashboard.json:**
```json
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/Lambda", "Invocations", {"stat": "Sum", "label": "Invocations"}],
          [".", "Errors", {"stat": "Sum", "label": "Errors"}],
          [".", "Duration", {"stat": "Average", "label": "Duration"}]
        ],
        "period": 300,
        "stat": "Average",
        "region": "us-east-1",
        "title": "Lambda Metrics",
        "dimensions": {
          "FunctionName": "email-app-generate-url-prod"
        }
      }
    }
  ]
}
```

---

## Summary

✅ **Quick Test:**
```bash
JWT_TOKEN=$(aws cognito-idp initiate-auth --auth-flow USER_PASSWORD_AUTH --client-id $(terraform output -raw cognito_client_id) --auth-parameters USERNAME=testuser@example.com,PASSWORD=TestPass123! --query 'AuthenticationResult.IdToken' --output text) && curl -X POST $(terraform output -raw api_gateway_url) -H "Authorization: Bearer $JWT_TOKEN" -H "Content-Type: application/json" -d '{"operation":"generate_url","s3_key":"emails/test-msg-001/test-document.pdf"}' | jq .
```

For detailed deployment steps, see [DEPLOYMENT.md](DEPLOYMENT.md)  
For cost analysis, see [README_COST.md](README_COST.md)  
For architecture details, see [README.md](README.md)
