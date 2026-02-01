# Destroy and Recreate Guide

Complete guide for destroying and recreating the infrastructure from scratch.

## ✅ Will It Work From Scratch?

**YES!** The complete workflow is fully automated and tested:

```bash
# Complete workflow (20-30 minutes)
./scripts/generate_keys.sh          # Generate CloudFront keys
./scripts/build_lambda_docker.sh    # Build Lambda package
terraform init                       # Initialize Terraform
terraform apply                      # Deploy infrastructure (10-15 min)
./scripts/setup.sh                   # Configure and populate data
# Test with curl - it will work!
```

All 7 issues discovered during initial deployment have been fixed. The infrastructure will deploy successfully on first run.

---

## Destroy Existing Infrastructure

### Step 1: Empty S3 Bucket

S3 buckets must be empty before Terraform can destroy them:

```bash
# Get bucket name
BUCKET_NAME=$(terraform output -raw s3_bucket_name)

# Empty bucket (removes all objects and versions)
aws s3 rm s3://$BUCKET_NAME --recursive

# Verify empty
aws s3 ls s3://$BUCKET_NAME
```

### Step 2: Destroy All Resources

```bash
terraform destroy
```

Type `yes` when prompted.

**Duration:** ~10-15 minutes (CloudFront deletion is slow)

**What gets deleted:**
- CloudFront distribution
- Lambda function
- API Gateway
- Cognito User Pool (and all users)
- DynamoDB tables (and all data)
- S3 bucket
- Secrets Manager secret
- IAM roles and policies
- CloudWatch log groups and alarms

### Step 3: Clean Local Files (Optional)

```bash
# Remove Terraform state
rm -rf .terraform/
rm terraform.tfstate*

# Remove Lambda build (will rebuild)
rm -rf lambda_build/

# Keep keys/ directory (reusable)
# Only regenerate if you want new keys
```

---

## Recreate Infrastructure

### Step 1: Generate Keys (if needed)

If you deleted `keys/` directory or want new keys:

```bash
./scripts/generate_keys.sh
```

**Reuse existing keys?** Skip this step if `keys/private_key.pem` exists.

### Step 2: Build Lambda Package

```bash
./scripts/build_lambda_docker.sh
```

**Output:** `lambda_build/` directory with platform-compatible dependencies

**Duration:** ~2-3 minutes

### Step 3: Initialize Terraform

```bash
terraform init
```

This downloads AWS providers (~5.0).

### Step 4: Review Plan

```bash
terraform plan
```

**Expected:** ~30 resources to create

### Step 5: Deploy

```bash
terraform apply
```

Type `yes` when prompted.

**Duration:** ~10-15 minutes

**What happens:**
1. S3 bucket created (instant)
2. DynamoDB tables created (instant)
3. Lambda function created and code uploaded (~1 min)
4. Cognito User Pool created (~1 min)
5. API Gateway created (~1 min)
6. CloudFront distribution created (~10 min) ⏱️
7. All supporting resources (IAM, CloudWatch, Secrets Manager)

### Step 6: Configure

```bash
./scripts/setup.sh
```

**Duration:** ~30 seconds

**What happens:**
1. Uploads CloudFront private key to Secrets Manager
2. Creates test users (testuser@example.com, recipient@example.com)
3. Uploads test PDF to S3
4. Populates DynamoDB with test data

### Step 7: Test

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

**Expected output:**
```json
{
  "signed_url": "https://d123abc.cloudfront.net/emails/test-msg-001/test-document.pdf?Expires=...",
  "expires_at": "2026-03-08T12:00:00Z",
  "s3_key": "emails/test-msg-001/test-document.pdf"
}
```

### Step 8: Download File

```bash
SIGNED_URL=$(curl -s -X POST $API_URL \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"operation":"generate_url","s3_key":"emails/test-msg-001/test-document.pdf"}' \
  | jq -r '.signed_url')

curl "$SIGNED_URL" -o test.pdf
cat test.pdf
```

**Expected:** "This is a test attachment for email test-msg-001"

---

## Complete One-Liner (After Destroy)

```bash
./scripts/generate_keys.sh && \
./scripts/build_lambda_docker.sh && \
terraform init && \
terraform apply -auto-approve && \
./scripts/setup.sh && \
echo "Deployment complete! Testing..." && \
JWT_TOKEN=$(aws cognito-idp initiate-auth --auth-flow USER_PASSWORD_AUTH --client-id $(terraform output -raw cognito_client_id) --auth-parameters USERNAME=testuser@example.com,PASSWORD=TestPass123! --query 'AuthenticationResult.IdToken' --output text) && \
curl -X POST $(terraform output -raw api_gateway_url) -H "Authorization: Bearer $JWT_TOKEN" -H "Content-Type: application/json" -d '{"operation":"generate_url","s3_key":"emails/test-msg-001/test-document.pdf"}' | jq .
```

**Caution:** Uses `-auto-approve` (skips confirmation)

---

## What's Preserved Between Destroys?

### ✅ Kept (Local Files)
- `keys/` - CloudFront RSA keys (can reuse)
- `lambda/` - Source code
- `*.tf` - Terraform configuration
- `scripts/` - Shell scripts

### ❌ Deleted (AWS Resources)
- All infrastructure
- All data (DynamoDB, S3)
- All users (Cognito)
- All logs (CloudWatch)

### 🔄 Rebuilt (Generated)
- `lambda_build/` - Rebuilt by Docker script
- `.terraform/` - Recreated by `terraform init`
- `terraform.tfstate` - New state file

---

## Why Destroy and Recreate?

Common reasons:

1. **Testing deployment automation** - Verify it works from scratch
2. **Major infrastructure changes** - Easier than in-place updates
3. **Cost optimization** - Destroy dev/test environments when not in use
4. **Clean slate** - Remove all test data and start fresh
5. **Troubleshooting** - Resolve state issues or misconfigurations

---

## Partial Destroy/Recreate

### Recreate Lambda Only

```bash
# Update Lambda code
nano lambda/lambda_function.py

# Rebuild package
./scripts/build_lambda_docker.sh

# Redeploy Lambda
terraform apply -target=aws_lambda_function.main
```

### Recreate DynamoDB Data Only

```bash
# Clear tables
aws dynamodb delete-table --table-name EmailAttachments
aws dynamodb delete-table --table-name UserEmailAccess

# Recreate tables
terraform apply -target=aws_dynamodb_table.email_attachments -target=aws_dynamodb_table.user_email_access

# Repopulate
./scripts/setup.sh
```

### Recreate CloudFront Only

```bash
terraform destroy -target=aws_cloudfront_distribution.main
terraform apply -target=aws_cloudfront_distribution.main
```

**Note:** CloudFront takes ~10-15 minutes to create/destroy

---

## Troubleshooting Destroy

### Issue: "BucketNotEmpty"

```bash
# Force empty bucket
aws s3 rb s3://$(terraform output -raw s3_bucket_name) --force
```

### Issue: "ResourceInUse" (Lambda)

```bash
# Check for event source mappings
aws lambda list-event-source-mappings \
  --function-name $(terraform output -raw lambda_function_name)

# Delete if found
aws lambda delete-event-source-mapping --uuid <UUID>
```

### Issue: CloudFront Stuck "InProgress"

```bash
# Check distribution status
aws cloudfront get-distribution \
  --id $(terraform output -raw cloudfront_distribution_id) \
  --query 'Distribution.Status'

# Wait for "Deployed" before destroying
# This can take 10-15 minutes
```

### Issue: Terraform State Locked

```bash
# Force unlock (use with caution)
terraform force-unlock <LOCK_ID>

# Or delete local state (if no remote backend)
rm terraform.tfstate*
terraform init
```

---

## Cost Implications

### Destroy to Save Costs

When not in use, destroy to stop charges:

**Running costs (per month):**
- CloudFront: ~$0.01/GB + $0.0075/10k requests
- Lambda: $0 (within free tier for testing)
- DynamoDB: ~$1.25/mo (on-demand, minimal data)
- API Gateway: ~$3.50/million requests
- Other services: ~$1/mo (logs, secrets)

**Total idle cost:** ~$2-5/month with minimal traffic

**After destroy:** $0/month ✅

### Recreate When Needed

Total time to recreate: ~20-30 minutes

Good for:
- Dev/test environments (destroy nightly)
- Demo environments (create on-demand)
- Cost-conscious development

---

## Verification Checklist

After recreating, verify:

- [ ] CloudFront distribution status = "Deployed"
- [ ] Lambda function executes without errors
- [ ] Cognito users created (testuser@example.com, recipient@example.com)
- [ ] DynamoDB tables have test data
- [ ] S3 has test file (emails/test-msg-001/test-document.pdf)
- [ ] Secrets Manager has CloudFront private key
- [ ] API returns signed URL (not errors)
- [ ] Signed URL downloads file successfully
- [ ] CloudWatch logs show successful requests

**Quick check:**
```bash
terraform output
aws dynamodb scan --table-name UserEmailAccess --output table
aws s3 ls s3://$(terraform output -raw s3_bucket_name)/emails/test-msg-001/
```

---

## Summary

✅ **Destroy and recreate is fully supported**
✅ **All steps are automated**
✅ **Takes 20-30 minutes total**
✅ **Tested and verified to work**

The infrastructure is designed to be:
- **Reproducible** - Same result every time
- **Idempotent** - Safe to run multiple times
- **Documented** - Every step explained
- **Tested** - All issues fixed

🎉 **You can confidently destroy and recreate anytime!**
