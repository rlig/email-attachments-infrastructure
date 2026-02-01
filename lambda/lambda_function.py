import json
import os
import datetime
import boto3
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.backends import default_backend
from botocore.signers import CloudFrontSigner
from authorization import (
    check_email_access,
    check_attachment_access,
    validate_user_attachment_batch
)

# Configuration from environment variables
CLOUDFRONT_DOMAIN = os.environ['CLOUDFRONT_DOMAIN']
KEY_PAIR_ID = os.environ['KEY_PAIR_ID']
SECRET_NAME = os.environ['SECRET_NAME']
AWS_REGION = os.environ.get('AWS_REGION', 'us-east-1')

secrets_client = boto3.client('secretsmanager', region_name=AWS_REGION)
_private_key_cache = None

def get_private_key():
    """Load private key from Secrets Manager with caching"""
    global _private_key_cache
    if _private_key_cache is None:
        response = secrets_client.get_secret_value(SecretId=SECRET_NAME)
        private_key_pem = response['SecretString'].encode('utf-8')
        _private_key_cache = serialization.load_pem_private_key(
            private_key_pem, password=None, backend=default_backend()
        )
    return _private_key_cache

def rsa_signer(message):
    """Sign message with RSA private key"""
    private_key = get_private_key()
    return private_key.sign(message, padding.PKCS1v15(), hashes.SHA1())

def generate_signed_url(s3_key, expiration_days=30):
    """Generate CloudFront signed URL"""
    url = f'https://{CLOUDFRONT_DOMAIN}/{s3_key}'
    expire_date = datetime.datetime.utcnow() + datetime.timedelta(days=expiration_days)
    
    cloudfront_signer = CloudFrontSigner(KEY_PAIR_ID, rsa_signer)
    signed_url = cloudfront_signer.generate_presigned_url(url, date_less_than=expire_date)
    
    return {
        'signed_url': signed_url,
        'expires_at': expire_date.isoformat() + 'Z',
        's3_key': s3_key
    }

def generate_signed_cookies(resource_path, expiration_days=30):
    """Generate CloudFront signed cookies"""
    import base64
    
    url = f'https://{CLOUDFRONT_DOMAIN}/{resource_path}'
    expire_date = datetime.datetime.utcnow() + datetime.timedelta(days=expiration_days)
    epoch_expire = int(expire_date.timestamp())
    
    policy = {
        "Statement": [{
            "Resource": url,
            "Condition": {
                "DateLessThan": {
                    "AWS:EpochTime": epoch_expire
                }
            }
        }]
    }
    
    policy_json = json.dumps(policy, separators=(',', ':'))
    policy_encoded = base64.b64encode(policy_json.encode('utf-8')).decode('utf-8')
    policy_encoded = policy_encoded.replace('+', '-').replace('=', '_').replace('/', '~')
    
    signature = rsa_signer(policy_json.encode('utf-8'))
    signature_encoded = base64.b64encode(signature).decode('utf-8')
    signature_encoded = signature_encoded.replace('+', '-').replace('=', '_').replace('/', '~')
    
    return {
        'CloudFront-Policy': policy_encoded,
        'CloudFront-Signature': signature_encoded,
        'CloudFront-Key-Pair-Id': KEY_PAIR_ID,
        'expires_at': expire_date.isoformat() + 'Z'
    }

def lambda_handler(event, context):
    """Main Lambda handler"""
    try:
        # Extract user ID from Cognito authorizer
        user_id = event.get('requestContext', {}).get('authorizer', {}).get('claims', {}).get('sub')
        
        # Fallback for direct invocation (testing)
        if not user_id:
            user_id = event.get('user_id')
        
        if not user_id:
            return {
                'statusCode': 401,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Unauthorized: user_id not found'})
            }
        
        # Parse body for API Gateway Lambda proxy integration
        if 'body' in event:
            try:
                body = json.loads(event['body'])
            except:
                body = event
        else:
            body = event
        
        operation = body.get('operation', 'generate_url')
        
        # Operation 1: Generate signed URL
        if operation == 'generate_url':
            s3_key = body.get('s3_key')
            expiration_days = body.get('expiration_days', 30)
            
            if not s3_key:
                return {
                    'statusCode': 400,
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps({'error': 's3_key is required'})
                }
            
            # Authorization check
            email_metadata = check_attachment_access(user_id, s3_key)
            if not email_metadata:
                return {
                    'statusCode': 403,
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps({'error': 'Access denied'})
                }
            
            result = generate_signed_url(s3_key, expiration_days)
            print(f"[AUDIT] user={user_id} generated_url s3_key={s3_key}")
            
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps(result)
            }
        
        # Operation 2: Generate signed cookies
        elif operation == 'generate_cookies':
            email_id = body.get('email_id')
            expiration_days = body.get('expiration_days', 7)
            
            if not email_id:
                return {
                    'statusCode': 400,
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps({'error': 'email_id is required'})
                }
            
            if not check_email_access(user_id, email_id):
                return {
                    'statusCode': 403,
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps({'error': 'Access denied'})
                }
            
            resource_path = f'emails/{email_id}/*'
            cookies = generate_signed_cookies(resource_path, expiration_days)
            print(f"[AUDIT] user={user_id} generated_cookies email_id={email_id}")
            
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps(cookies)
            }
        
        # Operation 3: Batch generate
        elif operation == 'batch_generate':
            s3_keys = body.get('s3_keys', [])
            expiration_days = body.get('expiration_days', 30)
            
            if not s3_keys:
                return {
                    'statusCode': 400,
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps({'error': 's3_keys list is required'})
                }
            
            authorized_keys = validate_user_attachment_batch(user_id, s3_keys)
            
            results = []
            for s3_key in authorized_keys:
                result = generate_signed_url(s3_key, expiration_days)
                results.append(result)
            
            print(f"[AUDIT] user={user_id} batch_generated count={len(results)}")
            
            return {
                'statusCode': 200,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({
                    'signed_urls': results,
                    'authorized_count': len(results),
                    'requested_count': len(s3_keys)
                })
            }
        
        else:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': f'Unknown operation: {operation}'})
            }
    
    except Exception as e:
        print(f"[ERROR] {str(e)}")
        import traceback
        traceback.print_exc()
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Internal server error'})
        }
