import boto3
from typing import Optional, List, Dict

dynamodb = boto3.resource('dynamodb')
emails_table = dynamodb.Table('EmailAttachments')
access_table = dynamodb.Table('UserEmailAccess')

def check_email_access(user_id: str, email_id: str) -> bool:
    """Check if user has access to email"""
    try:
        response = access_table.get_item(
            Key={'user_id': user_id, 'email_id': email_id}
        )
        return 'Item' in response
    except Exception as e:
        print(f"Error checking email access: {str(e)}")
        return False

def check_attachment_access(user_id: str, s3_key: str) -> Optional[Dict]:
    """Check if user has access to attachment"""
    try:
        # Extract email_id from s3_key pattern: emails/{email_id}/{filename}
        parts = s3_key.split('/')
        if len(parts) < 3 or parts[0] != 'emails':
            print(f"Invalid s3_key format: {s3_key}")
            return None
        
        email_id = parts[1]
        
        # Get the email record
        response = emails_table.get_item(Key={'email_id': email_id})
        
        if 'Item' not in response:
            print(f"Email not found: {email_id}")
            return None
        
        email = response['Item']
        
        # Verify the s3_key exists in attachments
        attachments = email.get('attachments', [])
        s3_key_found = False
        for attachment in attachments:
            if attachment.get('s3_key') == s3_key:
                s3_key_found = True
                break
        
        if not s3_key_found:
            print(f"S3 key not found in email attachments: {s3_key}")
            return None
        
        # Check if user has access to this email
        if check_email_access(user_id, email_id):
            return email
        
        print(f"User {user_id} does not have access to email {email_id}")
        return None
    except Exception as e:
        print(f"Error checking attachment access: {str(e)}")
        return None

def validate_user_attachment_batch(user_id: str, s3_keys: List[str]) -> List[str]:
    """Validate access to multiple attachments"""
    authorized_keys = []
    for s3_key in s3_keys:
        if check_attachment_access(user_id, s3_key):
            authorized_keys.append(s3_key)
    return authorized_keys
