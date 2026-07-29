variable "aws_region" {
  description = "Primary AWS region for provider and supporting resources"
  default     = "us-east-1"
}

variable "lambda_function_name" {
  description = "Name of the deployed Lambda function"
  default     = "ebs-guardian"
}

variable "notification_email" {
  description = "Email address that receives execution reports via SNS"
  default     = "your-email@example.com"
}

variable "schedule_expression" {
  description = "EventBridge schedule expression (rate or cron syntax)"
  default     = "cron(0 2 * * ? *)"  # 02:00 UTC daily
}

variable "retention_days" {
  description = "Number of days to retain managed snapshots before purging"
  type        = number
  default     = 7
}

variable "snapshot_tag_key" {
  description = "EC2 volume tag key that identifies volumes for backup"
  default     = "Snapshot"
}

variable "snapshot_tag_value" {
  description = "EC2 volume tag value that identifies volumes for backup"
  default     = "true"
}