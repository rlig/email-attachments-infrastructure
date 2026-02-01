#!/bin/bash
set -e

echo "======================================"
echo "Manual AWS Resource Cleanup"
echo "======================================"
echo ""
echo "⚠️  This will delete ALL email-app resources!"
echo "Press Ctrl+C to cancel, or Enter to continue..."
read

# Delete DynamoDB tables
echo "Deleting DynamoDB tables..."
aws dynamodb delete-table --table-name EmailAttachments 2>/dev/null || true
aws dynamodb delete-table --table-name UserEmailAccess 2>/dev/null || true

# Delete Lambda function
echo "Deleting Lambda function..."
aws lambda delete-function --function-name email-app-generate-url-prod 2>/dev/null || true
aws logs delete-log-group --log-group-name /aws/lambda/email-app-generate-url-prod 2>/dev/null || true

# Delete API Gateway
echo "Deleting API Gateway..."
API_ID=$(aws apigateway get-rest-apis --query 'items[?name==`email-app-prod`].id' --output text)
if [ ! -z "$API_ID" ]; then
  aws apigateway delete-rest-api --rest-api-id $API_ID
fi
aws logs delete-log-group --log-group-name /aws/apigateway/email-app-prod 2>/dev/null || true

# Delete Cognito User Pool
echo "Deleting Cognito User Pool..."
USER_POOL_ID=$(aws cognito-idp list-user-pools --max-results 20 --query 'UserPools[?Name==`email-app-prod`].Id' --output text)
if [ ! -z "$USER_POOL_ID" ]; then
  aws cognito-idp delete-user-pool-domain --domain email-app-prod --user-pool-id $USER_POOL_ID 2>/dev/null || true
  aws cognito-idp delete-user-pool --user-pool-id $USER_POOL_ID
fi

# Delete Secrets Manager secret
echo "Deleting Secrets Manager secret..."
aws secretsmanager delete-secret --secret-id email-app-cloudfront-private-key-prod --force-delete-without-recovery 2>/dev/null || true

# Empty and delete S3 bucket
echo "Emptying and deleting S3 bucket..."
BUCKET_NAME=$(aws s3 ls | grep email-app | awk '{print $3}')
if [ ! -z "$BUCKET_NAME" ]; then
  aws s3 rm s3://$BUCKET_NAME --recursive
  aws s3api delete-bucket --bucket $BUCKET_NAME
fi

# Delete CloudWatch alarms
echo "Deleting CloudWatch alarms..."
aws cloudwatch delete-alarms --alarm-names \
  email-app-lambda-errors-prod \
  email-app-api-errors-prod \
  email-app-dynamodb-throttle-prod 2>/dev/null || true

# CloudFront (must be disabled first - takes time)
echo "Disabling CloudFront distribution..."
echo "⚠️  This takes 10-15 minutes. You may need to run this manually later:"
echo ""
echo "1. Go to CloudFront console"
echo "2. Disable the distribution"
echo "3. Wait for deployment"
echo "4. Delete the distribution, key group, public key, and OAC"

# Delete IAM roles
echo "Deleting IAM roles..."
aws iam detach-role-policy --role-name email-app-lambda-role-prod --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
aws iam delete-role-policy --role-name email-app-lambda-role-prod --policy-name lambda-policy 2>/dev/null || true
aws iam delete-role --role-name email-app-lambda-role-prod 2>/dev/null || true

aws iam detach-role-policy --role-name email-app-api-gateway-cloudwatch-prod --policy-arn arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs 2>/dev/null || true
aws iam delete-role --role-name email-app-api-gateway-cloudwatch-prod 2>/dev/null || true

echo ""
echo "======================================"
echo "Cleanup Complete (except CloudFront)"
echo "======================================"
echo ""
echo "Manually delete CloudFront resources from AWS Console:"
echo "1. CloudFront distribution (disable first, wait, then delete)"
echo "2. CloudFront key group"
echo "3. CloudFront public key"
echo "4. CloudFront origin access control"
