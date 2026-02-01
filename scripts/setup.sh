#!/bin/bash
set -e

echo "======================================"
echo "Post-Deployment Setup Script"
echo "======================================"
echo ""

# Check if Terraform outputs are available
if ! terraform output > /dev/null 2>&1; then
    echo "❌ Error: Terraform outputs not found. Run 'terraform apply' first."
    exit 1
fi

# Get Terraform outputs
SECRET_NAME=$(terraform output -raw secrets_manager_secret_name)
USER_POOL_ID=$(terraform output -raw cognito_user_pool_id)
CLIENT_ID=$(terraform output -raw cognito_client_id)
BUCKET_NAME=$(terraform output -raw s3_bucket_name)
ATTACHMENTS_TABLE=$(terraform output -raw dynamodb_attachments_table)
ACCESS_TABLE=$(terraform output -raw dynamodb_access_table)

echo "1. Uploading CloudFront private key to Secrets Manager..."
aws secretsmanager put-secret-value \
    --secret-id "$SECRET_NAME" \
    --secret-string file://keys/private_key.pem
echo "✓ Private key uploaded"
echo ""

echo "2. Creating test users..."

# User 1: testuser@example.com (sender)
if aws cognito-idp admin-get-user --user-pool-id "$USER_POOL_ID" --username testuser@example.com >/dev/null 2>&1; then
    echo "  User 'testuser@example.com' already exists"
else
    echo "  Creating user 'testuser@example.com'..."
    aws cognito-idp admin-create-user \
        --user-pool-id "$USER_POOL_ID" \
        --username testuser@example.com \
        --user-attributes Name=email,Value=testuser@example.com \
        --message-action SUPPRESS
fi

aws cognito-idp admin-set-user-password \
    --user-pool-id "$USER_POOL_ID" \
    --username testuser@example.com \
    --password "TestPass123!" \
    --permanent \
    >/dev/null 2>&1 || true

# User 2: recipient@example.com (recipient)
if aws cognito-idp admin-get-user --user-pool-id "$USER_POOL_ID" --username recipient@example.com >/dev/null 2>&1; then
    echo "  User 'recipient@example.com' already exists"
else
    echo "  Creating user 'recipient@example.com'..."
    aws cognito-idp admin-create-user \
        --user-pool-id "$USER_POOL_ID" \
        --username recipient@example.com \
        --user-attributes Name=email,Value=recipient@example.com \
        --message-action SUPPRESS
fi

aws cognito-idp admin-set-user-password \
    --user-pool-id "$USER_POOL_ID" \
    --username recipient@example.com \
    --password "TestPass123!" \
    --permanent \
    >/dev/null 2>&1 || true

echo "✓ Test users created"
echo "  - testuser@example.com (password: TestPass123!)"
echo "  - recipient@example.com (password: TestPass123!)"
echo ""

echo "3. Uploading sample attachment to S3..."
# Create sample file in /tmp
TEMP_FILE="/tmp/test-document-$$.pdf"
echo "This is a test email attachment" > "$TEMP_FILE"

# Verify file was created
if [ ! -f "$TEMP_FILE" ]; then
    echo "❌ Error: Failed to create temporary file"
    exit 1
fi

# Change to /tmp to avoid special character issues in CWD
# AWS CLI tries to compute relative paths based on CWD
cd /tmp

# Upload to S3
if aws s3 cp "$TEMP_FILE" "s3://$BUCKET_NAME/emails/test-msg-001/test-document.pdf"; then
    echo "✓ Sample file uploaded"
    UPLOAD_SUCCESS=true
else
    echo "❌ Error: Failed to upload file to S3"
    UPLOAD_SUCCESS=false
fi

# Clean up
rm -f "$TEMP_FILE"

# Return to original directory
cd - > /dev/null

# Exit if upload failed
if [ "$UPLOAD_SUCCESS" != "true" ]; then
    exit 1
fi

echo ""

echo "4. Populating DynamoDB with sample data..."

# Get Cognito user IDs
echo "  Retrieving Cognito user IDs..."
TESTUSER_SUB=$(aws cognito-idp admin-get-user --user-pool-id "$USER_POOL_ID" --username testuser@example.com --query 'UserAttributes[?Name==`sub`].Value' --output text 2>&1)
if [ $? -ne 0 ]; then
    echo "❌ Error: Could not get testuser@example.com details. User may not exist."
    echo "   Try deleting and recreating the user:"
    echo "   aws cognito-idp admin-delete-user --user-pool-id $USER_POOL_ID --username testuser@example.com"
    echo "   Then run this script again."
    exit 1
fi

RECIPIENT_SUB=$(aws cognito-idp admin-get-user --user-pool-id "$USER_POOL_ID" --username recipient@example.com --query 'UserAttributes[?Name==`sub`].Value' --output text 2>&1)
if [ $? -ne 0 ]; then
    echo "❌ Error: Could not get recipient@example.com details. User may not exist."
    echo "   Try deleting and recreating the user:"
    echo "   aws cognito-idp admin-delete-user --user-pool-id $USER_POOL_ID --username recipient@example.com"
    echo "   Then run this script again."
    exit 1
fi

echo "  testuser@example.com sub: $TESTUSER_SUB"
echo "  recipient@example.com sub: $RECIPIENT_SUB"

# Add email metadata
aws dynamodb put-item \
    --table-name "$ATTACHMENTS_TABLE" \
    --item "{
        \"email_id\": {\"S\": \"test-msg-001\"},
        \"sender_user_id\": {\"S\": \"$TESTUSER_SUB\"},
        \"recipient_user_ids\": {\"L\": [{\"S\": \"$TESTUSER_SUB\"}, {\"S\": \"$RECIPIENT_SUB\"}]},
        \"subject\": {\"S\": \"Test Email\"},
        \"attachments\": {\"L\": [{\"M\": {
            \"s3_key\": {\"S\": \"emails/test-msg-001/test-document.pdf\"},
            \"filename\": {\"S\": \"test-document.pdf\"}
        }}]}
    }"

# Add access records
aws dynamodb put-item \
    --table-name "$ACCESS_TABLE" \
    --item "{
        \"user_id\": {\"S\": \"$TESTUSER_SUB\"},
        \"email_id\": {\"S\": \"test-msg-001\"},
        \"access_type\": {\"S\": \"sender\"}
    }"

aws dynamodb put-item \
    --table-name "$ACCESS_TABLE" \
    --item "{
        \"user_id\": {\"S\": \"$RECIPIENT_SUB\"},
        \"email_id\": {\"S\": \"test-msg-001\"},
        \"access_type\": {\"S\": \"recipient\"}
    }"

echo "✓ Sample data populated"
echo ""

echo "======================================"
echo "Setup Complete!"
echo "======================================"
echo ""
echo "Test users created:"
echo "  - testuser@example.com (Password: TestPass123!)"
echo "  - recipient@example.com (Password: TestPass123!)"
echo ""
echo "Test the deployment:"
echo ""
echo "1. Get JWT token:"
echo "   aws cognito-idp initiate-auth \\"
echo "     --auth-flow USER_PASSWORD_AUTH \\"
echo "     --client-id $CLIENT_ID \\"
echo "     --auth-parameters USERNAME=testuser@example.com,PASSWORD=TestPass123! \\"
echo "     | jq -r '.AuthenticationResult.IdToken'"
echo ""
echo "2. Generate signed URL:"
echo "   API_URL=\$(terraform output -raw api_gateway_url)"
echo "   curl -X POST \$API_URL \\"
echo "     -H \"Authorization: Bearer YOUR_JWT_TOKEN\" \\"
echo "     -H \"Content-Type: application/json\" \\"
echo "     -d '{\"operation\":\"generate_url\",\"s3_key\":\"emails/test-msg-001/test-document.pdf\"}'"
echo ""
echo "3. Open the signed_url in your browser to download the file"
echo ""
