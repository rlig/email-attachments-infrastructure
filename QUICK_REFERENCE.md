# Quick Reference Card

## 🚀 Deploy From Scratch (20-30 min)

```bash
./scripts/generate_keys.sh
./scripts/build_lambda_docker.sh
terraform init && terraform apply
./scripts/setup.sh
```

## 🧪 Test

```bash
JWT_TOKEN=$(aws cognito-idp initiate-auth --auth-flow USER_PASSWORD_AUTH --client-id $(terraform output -raw cognito_client_id) --auth-parameters USERNAME=testuser@example.com,PASSWORD=TestPass123! --query 'AuthenticationResult.IdToken' --output text)

curl -X POST $(terraform output -raw api_gateway_url) -H "Authorization: Bearer $JWT_TOKEN" -H "Content-Type: application/json" -d '{"operation":"generate_url","s3_key":"emails/test-msg-001/test-document.pdf"}' | jq .
```

## 💥 Destroy

```bash
aws s3 rm s3://$(terraform output -raw s3_bucket_name) --recursive
terraform destroy
```

## 📊 Check Status

```bash
# Lambda logs
aws logs tail /aws/lambda/$(terraform output -raw lambda_function_name) --follow

# DynamoDB data
aws dynamodb scan --table-name UserEmailAccess --output table

# CloudFront status
aws cloudfront get-distribution --id $(terraform output -raw cloudfront_distribution_id) --query 'Distribution.Status'
```

## 🔑 Test Users

- `testuser@example.com` / `TestPass123!`
- `recipient@example.com` / `TestPass123!`

## 📚 Documentation

- [WORKFLOW_SUMMARY.md](WORKFLOW_SUMMARY.md) - Complete overview
- [DEPLOYMENT.md](DEPLOYMENT.md) - Step-by-step guide
- [TESTING.md](TESTING.md) - All test commands
- [DESTROY_AND_RECREATE.md](DESTROY_AND_RECREATE.md) - Destroy guide

## ❓ Common Issues

| Error | Solution |
|-------|----------|
| `No module named 'cryptography'` | Run `./scripts/build_lambda_docker.sh` then `terraform apply` |
| `Access denied` | Run `./scripts/setup.sh` to populate DynamoDB |
| `Unauthorized` | Get fresh JWT token (expires in 1 hour) |
| `BucketNotEmpty` on destroy | Run `aws s3 rm s3://BUCKET --recursive` first |

## 💰 Cost (50 QPS)

~$812/month running, ~$2-5/month idle

## ✅ Production Ready

All 7 issues fixed, fully tested, complete automation!
