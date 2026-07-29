output "lambda_function_name" {
  description = "Name of the deployed ebs-guardian Lambda function"
  value       = aws_lambda_function.ebs_guardian.function_name
}

output "lambda_function_arn" {
  description = "ARN of the deployed ebs-guardian Lambda function"
  value       = aws_lambda_function.ebs_guardian.arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic used for execution reports"
  value       = aws_sns_topic.guardian_topic.arn
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge rule driving the backup schedule"
  value       = aws_cloudwatch_event_rule.schedule.arn
}

output "iam_role_arn" {
  description = "ARN of the IAM role assumed by the Lambda function"
  value       = aws_iam_role.lambda_exec_role.arn
}

output "log_group_name" {
  description = "CloudWatch Log Group name for Lambda execution logs"
  value       = aws_cloudwatch_log_group.guardian_logs.name
}
