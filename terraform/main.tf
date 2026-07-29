terraform {
  required_version = ">= 1.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------
# IAM Role — Lambda execution principal
# ---------------------------------------------------------------------------

resource "aws_iam_role" "lambda_exec_role" {
  name = "ebs-guardian-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
      Effect    = "Allow"
      Sid       = ""
    }]
  })

  tags = {
    Project = "ebs-guardian"
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Inline policy: least-privilege EBS + SNS + EC2 region discovery
resource "aws_iam_role_policy" "guardian_policy" {
  name = "ebs-guardian-policy"
  role = aws_iam_role.lambda_exec_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EBSSnapshotReadWrite"
        Effect = "Allow"
        Action = [
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots",
          "ec2:CreateSnapshot",
          "ec2:DeleteSnapshot",
          "ec2:CreateTags",
          "ec2:DescribeRegions",
        ]
        Resource = "*"
      },
      {
        Sid      = "SNSPublish"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.guardian_topic.arn
      },
    ]
  })
}

# ---------------------------------------------------------------------------
# CloudWatch Log Group — explicit retention control
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "guardian_logs" {
  name              = "/aws/lambda/${var.lambda_function_name}"
  retention_in_days = 30

  tags = {
    Project = "ebs-guardian"
  }
}

# ---------------------------------------------------------------------------
# Lambda Function
# ---------------------------------------------------------------------------

resource "aws_lambda_function" "ebs_guardian" {
  filename         = "lambda_function.zip"
  function_name    = var.lambda_function_name
  role             = aws_iam_role.lambda_exec_role.arn
  handler          = "lambda_function.lambda_handler"
  source_code_hash = filebase64sha256("lambda_function.zip")
  runtime          = "python3.12"
  timeout          = 300
  memory_size      = 256

  environment {
    variables = {
      SNS_TOPIC_ARN  = aws_sns_topic.guardian_topic.arn
      RETENTION_DAYS = tostring(var.retention_days)
      TAG_KEY        = var.snapshot_tag_key
      TAG_VALUE      = var.snapshot_tag_value
    }
  }

  depends_on = [aws_cloudwatch_log_group.guardian_logs]

  tags = {
    Project = "ebs-guardian"
  }
}

# ---------------------------------------------------------------------------
# SNS Topic + Subscription
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "guardian_topic" {
  name = "ebs-guardian-alerts"

  tags = {
    Project = "ebs-guardian"
  }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.guardian_topic.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

# ---------------------------------------------------------------------------
# EventBridge (CloudWatch Events) — scheduled trigger
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "ebs-guardian-schedule"
  description         = "Triggers ebs-guardian Lambda on a configurable schedule"
  schedule_expression = var.schedule_expression

  tags = {
    Project = "ebs-guardian"
  }
}

resource "aws_cloudwatch_event_target" "lambda_target" {
  rule      = aws_cloudwatch_event_rule.schedule.name
  target_id = "EbsGuardianLambda"
  arn       = aws_lambda_function.ebs_guardian.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ebs_guardian.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}