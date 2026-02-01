# How It Works

This document explains the architecture, security model, and operational details of the email attachments delivery system.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Complete Request Flow](#complete-request-flow)
- [CloudFront Signed URLs vs Signed Cookies](#cloudfront-signed-urls-vs-signed-cookies)
- [S3 Presigned URLs vs CloudFront Signed URLs](#s3-presigned-urls-vs-cloudfront-signed-urls)
- [Security Model](#security-model)
- [Component Details](#component-details)

---

## Architecture Overview

```
┌─────────────┐
│   Client    │
│  (Browser)  │
└──────┬──────┘
       │ 1. Request signed URL
       │    Authorization: Bearer JWT_TOKEN
       ▼
┌─────────────────┐
│  API Gateway    │──► Cognito Authorizer (validates JWT)
│   /generate-url │
└────────┬────────┘
         │ 2. Invoke with user_id
         ▼
┌──────────────────┐
│  Lambda Function │
│  - Check access  │◄──┐
│  - Sign URL      │   │ 3. Query access rights
│  - Return URL    │   │
└────────┬─────────┘   │
         │             │
         │             ▼
         │     ┌──────────────┐
         │     │   DynamoDB   │
         │     │ - EmailAttachments
         │     │ - UserEmailAccess
         │     └──────────────┘
         │
         │ 4. Fetch private key
         │
         ▼
┌──────────────────┐
│ Secrets Manager  │
│ CloudFront Key   │
└──────────────────┘
         
         │ 5. Return signed URL
         ▼
┌─────────────┐
│   Client    │
└──────┬──────┘
       │ 6. GET signed URL
       ▼
┌─────────────────┐
│   CloudFront    │
│ - Verify sig    │
│ - Check expiry  │
└────────┬────────┘
         │ 7. Fetch from origin
         ▼
┌─────────────────┐
│   S3 Bucket     │
│ (Private)       │
│ OAC Protected   │
└─────────────────┘
```

### Why This Architecture?

**Problem:** Email attachments need to be:
- Securely delivered only to authorized users
- Available via fast CDN (low latency worldwide)
- Protected from direct access
- Auditable (who accessed what)

**Solution:** CloudFront with signed URLs/cookies + custom authorization

---

## Complete Request Flow

### Phase 1: User Authentication (One-time)

```bash
# User logs in and gets JWT token
aws cognito-idp initiate-auth \
  --auth-flow USER_PASSWORD_AUTH \
  --client-id $CLIENT_ID \
  --auth-parameters USERNAME=user@example.com,PASSWORD=Pass123!
```

**Output:**
```json
{
  "AuthenticationResult": {
    "AccessToken": "eyJra...",
    "IdToken": "eyJra...",      ← This is used for API calls
    "RefreshToken": "eyJra...",
    "ExpiresIn": 3600
  }
}
```

**JWT Token Contains:**
- `sub`: User ID (Cognito UUID)
- `email`: User's email address
- `cognito:username`: Username
- `exp`: Token expiration
- Signature (validated by Cognito Authorizer)

### Phase 2: Request Signed URL

```bash
# Request signed URL for specific attachment
curl -X POST $API_URL \
  -H "Authorization: Bearer $JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "operation": "generate_url",
    "s3_key": "emails/msg-001/document.pdf",
    "expiration_days": 30
  }'
```

**Step-by-step:**

1. **API Gateway receives request**
   ```
   POST /prod/generate-url
   Authorization: Bearer eyJra...
   ```

2. **Cognito Authorizer validates JWT**
   - Verifies signature
   - Checks expiration
   - Extracts user claims
   - Passes `user_id` (sub claim) to Lambda

3. **Lambda receives enriched event**
   ```json
   {
     "requestContext": {
       "authorizer": {
         "claims": {
           "sub": "041864e8-0021-709a-cc7c-cfd7b3723b4e",
           "email": "user@example.com"
         }
       }
     },
     "body": "{\"operation\":\"generate_url\",\"s3_key\":\"emails/msg-001/document.pdf\"}"
   }
   ```

4. **Lambda checks authorization** (`authorization.py`)
   
   a. **Extract email_id from s3_key**
   ```python
   s3_key = "emails/msg-001/document.pdf"
   parts = s3_key.split('/')  # ["emails", "msg-001", "document.pdf"]
   email_id = parts[1]         # "msg-001"
   ```

   b. **Query EmailAttachments table**
   ```python
   # DynamoDB query
   emails_table.get_item(Key={'email_id': 'msg-001'})
   ```
   
   Returns:
   ```json
   {
     "email_id": "msg-001",
     "sender_user_id": "041864e8...",
     "recipient_user_ids": ["041864e8...", "44184418..."],
     "attachments": [
       {
         "s3_key": "emails/msg-001/document.pdf",
         "filename": "document.pdf"
       }
     ]
   }
   ```

   c. **Verify s3_key exists in attachments**
   ```python
   # Check if requested s3_key is in email's attachments
   for attachment in email['attachments']:
       if attachment['s3_key'] == s3_key:
           s3_key_found = True
   ```

   d. **Query UserEmailAccess table**
   ```python
   # Check if user has access to this email
   access_table.get_item(
       Key={
           'user_id': '041864e8-0021-709a-cc7c-cfd7b3723b4e',
           'email_id': 'msg-001'
       }
   )
   ```
   
   Returns:
   ```json
   {
     "user_id": "041864e8-0021-709a-cc7c-cfd7b3723b4e",
     "email_id": "msg-001",
     "access_type": "sender"  // or "recipient"
   }
   ```

   e. **Authorization decision**
   - If access record exists → **ALLOW**
   - If access record missing → **DENY** (403)

5. **Lambda generates signed URL**
   
   a. **Fetch private key from Secrets Manager** (cached in Lambda)
   ```python
   secrets_client.get_secret_value(SecretId='cloudfront/email-app-private-key-prod')
   ```

   b. **Create CloudFront signed URL**
   ```python
   # URL to sign
   url = f'https://{CLOUDFRONT_DOMAIN}/{s3_key}'
   # e.g., https://d1234abcd.cloudfront.net/emails/msg-001/document.pdf
   
   # Expiration
   expire_date = utcnow() + timedelta(days=30)
   
   # Sign with private key
   cloudfront_signer = CloudFrontSigner(KEY_PAIR_ID, rsa_signer)
   signed_url = cloudfront_signer.generate_presigned_url(url, date_less_than=expire_date)
   ```
   
   **Signed URL format:**
   ```
   https://d1234abcd.cloudfront.net/emails/msg-001/document.pdf?
   Expires=1740902400&
   Signature=base64_encoded_signature&
   Key-Pair-Id=K3SJ3JP0AZV5K7
   ```

   c. **Log audit trail**
   ```python
   print(f"[AUDIT] user=041864e8... generated_url s3_key=emails/msg-001/document.pdf")
   ```

6. **Lambda returns response**
   ```json
   {
     "statusCode": 200,
     "body": {
       "signed_url": "https://d1234abcd.cloudfront.net/emails/msg-001/document.pdf?Expires=...",
       "expires_at": "2025-03-01T12:00:00Z",
       "s3_key": "emails/msg-001/document.pdf"
     }
   }
   ```

### Phase 3: Download File

```bash
# Client uses signed URL to download
curl "https://d1234abcd.cloudfront.net/emails/msg-001/document.pdf?Expires=...&Signature=...&Key-Pair-Id=..."
```

**Step-by-step:**

1. **CloudFront receives request**
   - Extracts query parameters: `Expires`, `Signature`, `Key-Pair-Id`

2. **CloudFront verifies signature**
   - Looks up public key using `Key-Pair-Id`
   - Verifies signature using RSA-SHA1
   - Checks if current time < `Expires`
   
   **If valid:** Continue to origin
   **If invalid:** Return 403 Forbidden

3. **CloudFront fetches from S3**
   - Uses Origin Access Control (OAC)
   - S3 bucket policy ONLY allows CloudFront OAC
   - Direct S3 access is blocked

4. **CloudFront caches response**
   - Caches at edge locations
   - Subsequent requests from same region are faster
   - Cache respects `Expires` parameter

5. **Client receives file**
   - Content-Type header preserved
   - File downloads or displays in browser

---

## CloudFront Signed URLs vs Signed Cookies

### Signed URLs

**Use Case:** Single file access

**Example:**
```json
{
  "operation": "generate_url",
  "s3_key": "emails/msg-001/document.pdf"
}
```

**Response:**
```json
{
  "signed_url": "https://cdn.example.com/emails/msg-001/document.pdf?Expires=...&Signature=...&Key-Pair-Id=..."
}
```

**How it works:**
- URL contains signature in query parameters
- Each URL is unique and self-contained
- Can be shared (carefully!) but is tied to specific resource
- Signature validates: resource path + expiration

**Pros:**
- ✅ Simple to implement
- ✅ Works with any HTTP client
- ✅ URL is portable
- ✅ No cookie management needed

**Cons:**
- ❌ Long URLs (signature is ~300 chars)
- ❌ Need new URL for each file
- ❌ Signature visible in logs/history

**Implementation:**
```python
def generate_signed_url(s3_key, expiration_days=30):
    url = f'https://{CLOUDFRONT_DOMAIN}/{s3_key}'
    expire_date = datetime.utcnow() + timedelta(days=expiration_days)
    
    cloudfront_signer = CloudFrontSigner(KEY_PAIR_ID, rsa_signer)
    signed_url = cloudfront_signer.generate_presigned_url(
        url, 
        date_less_than=expire_date
    )
    
    return signed_url
```

### Signed Cookies

**Use Case:** Multiple files / folder access / embedded resources

**Example:**
```json
{
  "operation": "generate_cookies",
  "email_id": "msg-001"
}
```

**Response:**
```json
{
  "CloudFront-Policy": "eyJTdGF0ZW1lbnQiOlt7...",
  "CloudFront-Signature": "base64_signature",
  "CloudFront-Key-Pair-Id": "K3SJ3JP0AZV5K7",
  "expires_at": "2025-03-01T12:00:00Z"
}
```

**How it works:**
- Client sets cookies in browser
- All requests to CloudFront include cookies
- Policy can match wildcard patterns
- Signature validates: policy document

**Pros:**
- ✅ Clean URLs (no query params)
- ✅ Single authorization for multiple files
- ✅ Supports wildcards (`emails/msg-001/*`)
- ✅ Better for HTML pages with embedded resources

**Cons:**
- ❌ Requires cookie-capable client
- ❌ Must set cookies before requests
- ❌ Cookie management complexity
- ❌ Domain/path restrictions

**Policy Document:**
```json
{
  "Statement": [{
    "Resource": "https://cdn.example.com/emails/msg-001/*",
    "Condition": {
      "DateLessThan": {
        "AWS:EpochTime": 1740902400
      }
    }
  }]
}
```

**Implementation:**
```python
def generate_signed_cookies(resource_path, expiration_days=30):
    url = f'https://{CLOUDFRONT_DOMAIN}/{resource_path}'
    expire_date = datetime.utcnow() + timedelta(days=expiration_days)
    
    # Create policy
    policy = {
        "Statement": [{
            "Resource": url,
            "Condition": {
                "DateLessThan": {
                    "AWS:EpochTime": int(expire_date.timestamp())
                }
            }
        }]
    }
    
    # Encode and sign
    policy_json = json.dumps(policy, separators=(',', ':'))
    policy_encoded = base64.b64encode(policy_json.encode()).decode()
    signature = rsa_signer(policy_json.encode())
    signature_encoded = base64.b64encode(signature).decode()
    
    # CloudFront requires URL-safe base64
    policy_encoded = policy_encoded.replace('+', '-').replace('=', '_').replace('/', '~')
    signature_encoded = signature_encoded.replace('+', '-').replace('=', '_').replace('/', '~')
    
    return {
        'CloudFront-Policy': policy_encoded,
        'CloudFront-Signature': signature_encoded,
        'CloudFront-Key-Pair-Id': KEY_PAIR_ID
    }
```

**Client Usage:**
```javascript
// Set cookies
const cookies = response.cookies;
document.cookie = `CloudFront-Policy=${cookies['CloudFront-Policy']}; Domain=.cloudfront.net; Secure`;
document.cookie = `CloudFront-Signature=${cookies['CloudFront-Signature']}; Domain=.cloudfront.net; Secure`;
document.cookie = `CloudFront-Key-Pair-Id=${cookies['CloudFront-Key-Pair-Id']}; Domain=.cloudfront.net; Secure`;

// Now all requests to CloudFront will include these cookies
fetch('https://cdn.example.com/emails/msg-001/file1.pdf');
fetch('https://cdn.example.com/emails/msg-001/file2.pdf');
```

### When to Use Each?

| Scenario | Recommendation | Reason |
|----------|---------------|--------|
| Single file download | Signed URL | Simple, no cookie setup |
| Multiple attachments in email | Signed Cookies | One auth for all files |
| API/mobile app | Signed URL | Cookies are complex in apps |
| Web app with email viewer | Signed Cookies | HTML with embedded images |
| Sharing link externally | Signed URL | Portable, works anywhere |
| Long-lived access | Signed Cookies | Can refresh without new URLs |

---

## S3 Presigned URLs vs CloudFront Signed URLs

### S3 Presigned URLs

**What they are:**
- URL with temporary AWS credentials
- Direct access to S3 object
- Generated using AWS SDKs/boto3

**Example:**
```python
s3_client = boto3.client('s3')
url = s3_client.generate_presigned_url(
    'get_object',
    Params={'Bucket': 'my-bucket', 'Key': 'file.pdf'},
    ExpiresIn=3600  # seconds
)
```

**Generated URL:**
```
https://my-bucket.s3.amazonaws.com/file.pdf?
AWSAccessKeyId=AKIAIOSFODNN7EXAMPLE&
Expires=1740902400&
Signature=signature_here
```

**How they work:**
1. URL includes temporary AWS credentials
2. S3 validates credentials using AWS Signature V4
3. Direct connection to S3 (no CDN)

### CloudFront Signed URLs

**What they are:**
- URL with CloudFront signature
- Access via CloudFront CDN
- Uses RSA key pair (not AWS credentials)

**Example:**
```python
from botocore.signers import CloudFrontSigner

signer = CloudFrontSigner(key_pair_id, rsa_signer_function)
url = signer.generate_presigned_url(
    'https://cdn.example.com/file.pdf',
    date_less_than=expire_date
)
```

**Generated URL:**
```
https://d1234abcd.cloudfront.net/file.pdf?
Expires=1740902400&
Signature=base64_signature&
Key-Pair-Id=K3SJ3JP0AZV5K7
```

**How they work:**
1. URL includes RSA signature
2. CloudFront validates using public key
3. CloudFront fetches from origin (S3)
4. Response cached at edge locations

### Comparison Table

| Feature | S3 Presigned URL | CloudFront Signed URL |
|---------|------------------|----------------------|
| **Performance** | Direct S3 access | CDN (edge caching) |
| **Latency** | Depends on S3 region | Low (edge locations) |
| **Cost** | S3 data transfer | CloudFront pricing |
| **Global delivery** | Slow from far regions | Fast globally |
| **Signature type** | AWS Signature V4 | RSA-SHA1 |
| **Key management** | AWS credentials | RSA key pair |
| **Max expiration** | 7 days (best practice) | Any duration |
| **Audit trail** | S3 access logs | CloudFront logs |
| **Origin protection** | Bucket can be public | Bucket must be private (OAC) |
| **DDoS protection** | Limited | AWS Shield |
| **Custom domain** | Requires setup | Easy with ACM |
| **Revocation** | Wait for expiration | Delete public key |

### Why We Use CloudFront Signed URLs

1. **Performance**: Global edge network
   - 450+ edge locations worldwide
   - < 50ms latency in most regions
   - S3 presigned URLs have single-region latency

2. **Cost optimization**:
   - CloudFront caching reduces S3 requests
   - Free tier: 1TB/month CloudFront data transfer
   - Popular files served from cache

3. **Security**:
   - Origin (S3) completely private
   - S3 bucket policy only allows CloudFront OAC
   - No direct S3 access possible
   - CloudFront provides DDoS protection

4. **Flexibility**:
   - Longer expiration times (30 days+)
   - Wildcard patterns with signed cookies
   - Easy revocation (rotate key pair)

5. **User experience**:
   - Clean CloudFront URLs
   - Fast downloads worldwide
   - Built-in compression

### Example: Performance Comparison

**Scenario:** User in Sydney downloading 5MB file from us-east-1

**S3 Presigned URL:**
```
Latency: ~200ms (Sydney → Virginia)
Transfer time: ~8 seconds
Total: ~8.2 seconds
Cost: $0.0009 (S3 transfer)
```

**CloudFront Signed URL:**
```
First request:
  Latency: ~20ms (Sydney → Sydney edge)
  CloudFront → S3: ~200ms
  Transfer time: ~1 second (cached at edge)
  Total: ~1.2 seconds

Subsequent requests:
  Latency: ~20ms (served from cache)
  Transfer time: ~1 second
  Total: ~1 second
  
Cost: $0.00085 (CloudFront transfer)
```

**Result:** 7x faster with CloudFront, especially for cached content!

### Example: Security Comparison

**S3 Presigned URL:**
```bash
# Bucket policy allows presigned URLs
{
  "Effect": "Allow",
  "Principal": "*",
  "Action": "s3:GetObject",
  "Resource": "arn:aws:s3:::my-bucket/*",
  "Condition": {
    "StringEquals": {
      "s3:ExistingObjectTag/public": "yes"
    }
  }
}

# Problem: Bucket is partially public
# Anyone can try to access if they guess URL
```

**CloudFront Signed URL:**
```bash
# S3 bucket policy ONLY allows CloudFront OAC
{
  "Effect": "Allow",
  "Principal": {
    "Service": "cloudfront.amazonaws.com"
  },
  "Action": "s3:GetObject",
  "Resource": "arn:aws:s3:::my-bucket/*",
  "Condition": {
    "StringEquals": {
      "AWS:SourceArn": "arn:aws:cloudfront::ACCOUNT:distribution/ID"
    }
  }
}

# Result: S3 bucket is completely private
# Only CloudFront can access
# Direct S3 access returns 403
```

---

## Security Model

### Multi-Layer Security

```
Layer 1: Authentication (Cognito)
         ↓
Layer 2: API Authorization (JWT validation)
         ↓
Layer 3: Resource Authorization (DynamoDB ACL)
         ↓
Layer 4: Signed URL/Cookie (CloudFront signature)
         ↓
Layer 5: Origin Protection (OAC)
```

### Layer 1: User Authentication

**Cognito User Pool:**
- Email as username
- Password requirements: 8+ chars, uppercase, lowercase, numbers
- MFA available (optional)
- Account recovery via email

**JWT Token:**
```json
{
  "sub": "041864e8-0021-709a-cc7c-cfd7b3723b4e",
  "email": "user@example.com",
  "cognito:username": "041864e8-0021-709a-cc7c-cfd7b3723b4e",
  "iss": "https://cognito-idp.us-east-1.amazonaws.com/us-east-1_XXXXX",
  "exp": 1740902400,
  "iat": 1740898800
}
```

### Layer 2: API Authorization

**API Gateway Cognito Authorizer:**
- Validates JWT signature
- Checks token expiration
- Verifies issuer
- Passes `user_id` to Lambda

**No valid token = 401 Unauthorized**

### Layer 3: Resource Authorization

**DynamoDB Access Control:**

**EmailAttachments Table:**
```
PK: email_id
Attributes:
  - sender_user_id
  - recipient_user_ids (list)
  - attachments (list of s3_keys)
  - subject
```

**UserEmailAccess Table:**
```
PK: user_id
SK: email_id
Attributes:
  - access_type (sender/recipient)
```

**Authorization Logic:**
```python
def check_attachment_access(user_id, s3_key):
    # 1. Extract email_id from s3_key
    email_id = extract_email_id(s3_key)
    
    # 2. Get email metadata
    email = get_email(email_id)
    
    # 3. Verify s3_key is in email's attachments
    if s3_key not in email['attachments']:
        return False
    
    # 4. Check user has access to email
    access = get_user_access(user_id, email_id)
    
    return access is not None
```

**Access Denied = 403 Forbidden**

### Layer 4: Signed URL/Cookie

**CloudFront Signature Validation:**
- Validates RSA signature using public key
- Checks expiration timestamp
- Ensures URL hasn't been tampered with

**Invalid signature = 403 Forbidden**

### Layer 5: Origin Protection

**S3 Bucket Policy:**
```json
{
  "Effect": "Allow",
  "Principal": {
    "Service": "cloudfront.amazonaws.com"
  },
  "Action": "s3:GetObject",
  "Resource": "arn:aws:s3:::email-app-attachments/*",
  "Condition": {
    "StringEquals": {
      "AWS:SourceArn": "arn:aws:cloudfront::ACCOUNT:distribution/E123"
    }
  }
}
```

**Direct S3 access = 403 Forbidden**

### Attack Scenarios & Mitigations

#### Scenario 1: Stolen JWT Token

**Attack:** Attacker steals JWT token from user's browser

**Mitigations:**
1. Short token lifetime (1 hour)
2. Resource-level authorization (DynamoDB ACL)
   - Token only gives access to API
   - Lambda checks user has permission for specific file
3. Audit logging
   - All access logged with user_id
   - Can detect abnormal patterns

**Outcome:** Attacker can only access files the legitimate user can access, and only for 1 hour

#### Scenario 2: Stolen Signed URL

**Attack:** Attacker intercepts signed URL

**Mitigations:**
1. HTTPS only (TLS encryption)
2. Short expiration (configurable, default 30 days)
3. URL is tied to specific resource
4. Can revoke access by rotating CloudFront key pair

**Outcome:** Limited time window, limited to single file

#### Scenario 3: Direct S3 Access Attempt

**Attack:** Attacker tries to access S3 directly

**S3 URL:**
```
https://email-app-attachments.s3.amazonaws.com/emails/msg-001/file.pdf
```

**Result:**
```xml
<Error>
  <Code>AccessDenied</Code>
  <Message>Access Denied</Message>
</Error>
```

**Reason:** S3 bucket policy ONLY allows CloudFront OAC

#### Scenario 4: Brute Force Attachment Discovery

**Attack:** Attacker tries to guess s3_keys

**Request:**
```json
{
  "operation": "generate_url",
  "s3_key": "emails/msg-999/guessed-file.pdf"
}
```

**Lambda checks:**
1. Does email `msg-999` exist? (DynamoDB query)
2. Does user have access to `msg-999`? (DynamoDB query)
3. Does `guessed-file.pdf` exist in email's attachments?

**Result:** 403 Forbidden (access denied)

**Mitigation:** Resource-level authorization prevents fishing

---

## Component Details

### S3 Bucket Configuration

**Security:**
```terraform
# Block all public access
resource "aws_s3_bucket_public_access_block" "attachments" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Server-side encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "attachments" {
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Versioning
resource "aws_s3_bucket_versioning" "attachments" {
  versioning_configuration {
    status = "Enabled"
  }
}
```

**Lifecycle:**
```terraform
resource "aws_s3_bucket_lifecycle_configuration" "attachments" {
  rule {
    id     = "transition-to-glacier"
    status = "Enabled"
    
    transition {
      days          = 365
      storage_class = "GLACIER"
    }
  }
  
  rule {
    id     = "delete-old-versions"
    status = "Enabled"
    
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}
```

### CloudFront Distribution

**Origin Access Control (OAC):**
- Replaces legacy Origin Access Identity (OAI)
- Better security with AWS Signature V4
- Supports all S3 features

**Caching Behavior:**
```terraform
default_cache_behavior {
  allowed_methods        = ["GET", "HEAD", "OPTIONS"]
  cached_methods         = ["GET", "HEAD"]
  compress               = true
  default_ttl            = 86400    # 24 hours
  max_ttl                = 31536000 # 365 days
  viewer_protocol_policy = "redirect-to-https"
  
  trusted_key_groups = [aws_cloudfront_key_group.signing.id]
}
```

**Key Group:**
- Associates CloudFront distribution with public key
- Required for signed URL validation
- Can have multiple keys (for rotation)

### Lambda Function

**Runtime:** Python 3.12

**Memory:** 512 MB (optimized for cryptography operations)

**Timeout:** 30 seconds

**Environment Variables:**
```bash
CLOUDFRONT_DOMAIN=d1234abcd.cloudfront.net
KEY_PAIR_ID=K3SJ3JP0AZV5K7
SECRET_NAME=cloudfront/email-app-private-key-prod
AWS_REGION=us-east-1
```

**IAM Permissions:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:*:*:secret:cloudfront/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:Query"
      ],
      "Resource": [
        "arn:aws:dynamodb:*:*:table/EmailAttachments",
        "arn:aws:dynamodb:*:*:table/UserEmailAccess"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    }
  ]
}
```

**Cold Start Optimization:**
- Private key cached in global variable
- DynamoDB clients initialized once
- Typically < 1 second cold start

### DynamoDB Tables

**EmailAttachments Table:**
```
Partition Key: email_id (String)
Attributes:
  - sender_user_id: String
  - recipient_user_ids: List<String>
  - subject: String
  - attachments: List<Map>
    - s3_key: String
    - filename: String
  - created_at: Number
  - updated_at: Number

GSI: SenderIndex
  - Partition Key: sender_user_id
  - Projection: ALL
```

**UserEmailAccess Table:**
```
Partition Key: user_id (String)
Sort Key: email_id (String)
Attributes:
  - access_type: String (sender|recipient)
  - granted_at: Number
```

**Billing Mode:** PAY_PER_REQUEST (on-demand)
- No capacity planning needed
- Scales automatically
- Pay only for requests

**Point-in-Time Recovery:** Enabled
- Continuous backups for 35 days
- Restore to any point in time

---

## Monitoring & Logging

### CloudWatch Logs

**Lambda Logs:**
```
/aws/lambda/email-app-generate-url-prod
```

**API Gateway Logs:**
```
/aws/apigateway/email-app-prod
```

**Log Retention:** 14 days

### CloudWatch Alarms

**Lambda Errors:**
- Metric: `Errors`
- Threshold: > 10 errors in 5 minutes
- Action: (Configure SNS topic)

**API Gateway 4XX Errors:**
- Metric: `4XXError`
- Threshold: > 100 errors in 5 minutes
- Indicates: Authentication/authorization issues

**DynamoDB Throttles:**
- Metric: `UserErrors`
- Threshold: > 10 in 5 minutes
- Indicates: Capacity issues

### Audit Trail

**Lambda logs all operations:**
```python
print(f"[AUDIT] user={user_id} generated_url s3_key={s3_key}")
print(f"[AUDIT] user={user_id} generated_cookies email_id={email_id}")
print(f"[AUDIT] user={user_id} batch_generated count={count}")
```

**CloudWatch Insights Query:**
```sql
fields @timestamp, @message
| filter @message like /\[AUDIT\]/
| stats count() by user_id
| sort count desc
```

---

## Cost Analysis

See [README_COST.md](README_COST.md) for detailed cost breakdown.

**Summary for 1000 users, 10,000 emails/month:**
- CloudFront: $4.25/month
- Lambda: $0.20/month
- DynamoDB: $1.25/month
- S3: $2.30/month
- API Gateway: $3.50/month
- **Total: ~$11.50/month**

---

## Best Practices

### Security

1. **Rotate CloudFront key pairs annually**
   ```bash
   ./scripts/generate_keys.sh
   terraform apply  # Upload new public key
   # Update secret with new private key
   # Delete old public key after verification
   ```

2. **Use short JWT token lifetimes**
   - Default: 1 hour
   - Refresh tokens for long-lived sessions

3. **Enable MFA for administrative users**
   ```bash
   aws cognito-idp set-user-mfa-preference \
     --user-pool-id $USER_POOL_ID \
     --username admin@example.com \
     --software-token-mfa-settings Enabled=true
   ```

4. **Regular security audits**
   - Review CloudWatch logs
   - Check for unusual access patterns
   - Validate IAM policies

### Performance

1. **CloudFront cache tuning**
   - Increase TTL for static attachments
   - Use cache invalidation sparingly

2. **Lambda optimization**
   - Keep deployment package small
   - Use AWS X-Ray for tracing
   - Monitor cold start metrics

3. **DynamoDB optimization**
   - Use GSI for sender queries
   - Enable DynamoDB Accelerator (DAX) for high traffic

### Operational

1. **Monitoring**
   - Set up SNS topics for alarms
   - Create dashboard in CloudWatch

2. **Backup**
   - S3 versioning enabled
   - DynamoDB point-in-time recovery enabled
   - Regular Terraform state backups

3. **Disaster Recovery**
   - Document recovery procedures
   - Test restore process
   - Keep infrastructure as code updated

---

## Troubleshooting

### Issue: 403 Forbidden from CloudFront

**Possible Causes:**
1. Signature expired
2. Invalid signature
3. Incorrect Key-Pair-Id

**Debug:**
```bash
# Check expiration
echo "$URL" | grep -oP 'Expires=\K[0-9]+'
date -d @1740902400  # Convert to human-readable

# Verify Key-Pair-Id matches CloudFront public key
terraform output cloudfront_public_key_id
```

### Issue: 403 Access Denied from Lambda

**Possible Causes:**
1. User doesn't have access to email
2. S3 key not in email's attachments
3. Email doesn't exist

**Debug:**
```bash
# Check DynamoDB
aws dynamodb get-item \
  --table-name UserEmailAccess \
  --key '{"user_id":{"S":"USER_ID"},"email_id":{"S":"EMAIL_ID"}}'

# Check Lambda logs
aws logs tail /aws/lambda/email-app-generate-url-prod --follow
```

### Issue: 401 Unauthorized from API Gateway

**Possible Causes:**
1. JWT token missing
2. JWT token expired
3. Invalid JWT signature

**Debug:**
```bash
# Decode JWT (don't use expired tokens)
echo $JWT_TOKEN | jq -R 'split(".") | .[1] | @base64d | fromjson'

# Get new token
JWT_TOKEN=$(aws cognito-idp initiate-auth ...)
```

---

## Further Reading

- [CloudFront Signed URLs Documentation](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-signed-urls.html)
- [CloudFront Origin Access Control](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html)
- [API Gateway Cognito Authorizers](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-integrate-with-cognito.html)
- [DynamoDB Best Practices](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/best-practices.html)
