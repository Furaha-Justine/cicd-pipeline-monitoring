data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  cloudtrail_bucket_name = "${var.project_name}-cloudtrail-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
}

# ── CloudWatch log group for app container logs ───────────────────────────────
resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "/${var.project_name}/app"
  retention_in_days = 30
}

# ── S3 bucket for CloudTrail logs ─────────────────────────────────────────────
resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket        = local.cloudtrail_bucket_name
  force_destroy = true

  tags = {
    Name = "${var.project_name}-cloudtrail-logs"
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  bucket                  = aws_s3_bucket.cloudtrail_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = var.cloudtrail_sse_algorithm
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    id     = "DeleteLogsAfter30Days"
    status = "Enabled"

    filter {
      prefix = ""
    }

    expiration {
      days = 30
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail_logs.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# ── CloudTrail ────────────────────────────────────────────────────────────────
resource "aws_cloudtrail" "account_trail" {
  name                          = "${var.project_name}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  enable_logging                = true

  depends_on = [aws_s3_bucket_policy.cloudtrail_logs]
}

# ── GuardDuty ─────────────────────────────────────────────────────────────────
resource "terraform_data" "guardduty_enable" {
  provisioner "local-exec" {
    command = "aws guardduty create-detector --enable --finding-publishing-frequency FIFTEEN_MINUTES --region ${var.aws_region} >/dev/null 2>&1 || true"
  }
}
