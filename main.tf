# DynamoDB TTL Infrastructure
# This Terraform configuration creates a DynamoDB table with TTL enabled for automated data expiration

# Generate random suffix for unique resource naming
resource "random_id" "suffix" {
  byte_length = 3
}

# Local values for consistent resource naming and configuration
locals {
  table_name = "${var.table_name_prefix}-${random_id.suffix.hex}"
  
  # Common tags to be applied to all resources
  common_tags = merge(
    {
      Environment   = var.environment
      Project       = "DynamoDB-TTL-Demo"
      ManagedBy     = "Terraform"
      Recipe        = "simple-data-expiration-dynamodb-ttl"
      CostCenter    = var.cost_center
      Owner         = var.owner
      TableName     = local.table_name
    },
    var.additional_tags
  )

  # Calculate TTL timestamps for sample data
  current_time = timestamp()
  short_ttl    = timeadd(local.current_time, "5m")   # 5 minutes from now
  medium_ttl   = timeadd(local.current_time, "15m")  # 15 minutes from now
  long_ttl     = timeadd(local.current_time, "30m")  # 30 minutes from now
  past_ttl     = timeadd(local.current_time, "-1h")  # 1 hour ago (expired)
}

# DynamoDB table for session data with composite primary key
resource "aws_dynamodb_table" "session_table" {
  name           = local.table_name
  billing_mode   = var.billing_mode
  hash_key       = "user_id"
  range_key      = "session_id"

  # Provisioned capacity settings (only used if billing_mode is PROVISIONED)
  read_capacity  = var.billing_mode == "PROVISIONED" ? var.read_capacity : null
  write_capacity = var.billing_mode == "PROVISIONED" ? var.write_capacity : null

  # Define table attributes for primary key
  attribute {
    name = "user_id"
    type = "S"  # String type
  }

  attribute {
    name = "session_id"
    type = "S"  # String type
  }

  # TTL configuration for automatic data expiration
  ttl {
    attribute_name = var.ttl_attribute_name
    enabled        = true
  }

  # Point-in-time recovery configuration
  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  # Server-side encryption configuration
  server_side_encryption {
  enabled     = var.enable_server_side_encryption
  kms_key_arn = var.kms_key_id != "" ? var.kms_key_id : null
}

  # Prevent accidental deletion of the table
  deletion_protection_enabled = false

  tags = merge(local.common_tags, {
    Name        = local.table_name
    Description = "DynamoDB table for session data with TTL-based expiration"
    TTLEnabled  = "true"
    TTLAttribute = var.ttl_attribute_name
  })

  lifecycle {
  ignore_changes = [read_capacity, write_capacity]
}
}

# CloudWatch Log Group for DynamoDB monitoring (if monitoring is enabled)
resource "aws_cloudwatch_log_group" "dynamodb_logs" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0

  name              = "/aws/dynamodb/${local.table_name}"
  retention_in_days = 14

  tags = merge(local.common_tags, {
    Name        = "DynamoDB-TTL-Logs"
    Description = "CloudWatch logs for DynamoDB TTL monitoring"
  })
}

# CloudWatch Alarm for TTL deletions (if monitoring is enabled)
resource "aws_cloudwatch_metric_alarm" "ttl_deletions" {
  count = var.enable_cloudwatch_monitoring ? 1 : 0

  alarm_name          = "${local.table_name}-ttl-deletions"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "TimeToLiveDeletedItemCount"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors TTL deletions for ${local.table_name}"
  alarm_actions       = []  # Add SNS topic ARN if notifications are needed

  dimensions = {
    TableName = aws_dynamodb_table.session_table.name
  }

  tags = merge(local.common_tags, {
    Name        = "${local.table_name}-ttl-alarm"
    Description = "CloudWatch alarm for TTL deletion monitoring"
  })

  depends_on = [aws_dynamodb_table.session_table]
}
resource "null_resource" "sample_data" {
  count = var.create_sample_data ? 1 : 0

  # Re-runs only if the table itself changes
  triggers = {
    table_name = aws_dynamodb_table.session_table.name
  }

  provisioner "local-exec" {
    command = <<-EOT
      CURRENT_TIME=$(date +%s)
      SHORT_TTL=$((CURRENT_TIME + 300))
      LONG_TTL=$((CURRENT_TIME + 1800))
      PAST_TTL=$((CURRENT_TIME - 3600))

      aws dynamodb put-item --region ${var.aws_region} \
        --table-name ${aws_dynamodb_table.session_table.name} \
        --item '{"user_id":{"S":"user123"},"session_id":{"S":"session_active"},"session_type":{"S":"active"},"${var.ttl_attribute_name}":{"N":"'$LONG_TTL'"}}'

      aws dynamodb put-item --region ${var.aws_region} \
        --table-name ${aws_dynamodb_table.session_table.name} \
        --item '{"user_id":{"S":"user456"},"session_id":{"S":"session_temp"},"session_type":{"S":"temporary"},"${var.ttl_attribute_name}":{"N":"'$SHORT_TTL'"}}'

      aws dynamodb put-item --region ${var.aws_region} \
        --table-name ${aws_dynamodb_table.session_table.name} \
        --item '{"user_id":{"S":"user789"},"session_id":{"S":"session_expired"},"session_type":{"S":"expired"},"${var.ttl_attribute_name}":{"N":"'$PAST_TTL'"}}'
    EOT
  }

  depends_on = [aws_dynamodb_table.session_table]
}

# Data source to get current AWS caller identity for account ID
data "aws_caller_identity" "current" {}

# Data source to get current AWS region
data "aws_region" "current" {}


