# DynamoDB table for email attachments metadata
resource "aws_dynamodb_table" "email_attachments" {
  name           = "EmailAttachments"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "email_id"

  attribute {
    name = "email_id"
    type = "S"
  }

  attribute {
    name = "sender_user_id"
    type = "S"
  }

  # GSI for sender lookups
  global_secondary_index {
    name            = "SenderIndex"
    hash_key        = "sender_user_id"
    projection_type = "ALL"
    read_capacity   = var.dynamodb_billing_mode == "PROVISIONED" ? 5 : null
    write_capacity  = var.dynamodb_billing_mode == "PROVISIONED" ? 5 : null
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name = "EmailAttachments"
  }
}

# DynamoDB table for user email access mappings
resource "aws_dynamodb_table" "user_email_access" {
  name           = "UserEmailAccess"
  billing_mode   = var.dynamodb_billing_mode
  hash_key       = "user_id"
  range_key      = "email_id"

  attribute {
    name = "user_id"
    type = "S"
  }

  attribute {
    name = "email_id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name = "UserEmailAccess"
  }
}
