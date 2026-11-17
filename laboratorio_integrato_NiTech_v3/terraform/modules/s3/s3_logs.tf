resource "aws_s3_bucket" "waf_logs" {
  bucket        = var.waf_logs_bucket_name
  force_destroy = true

  tags = { Name = "${var.environment}-WAF-Audit-Logs" }
}

# Blocco completo dell'accesso pubblico
resource "aws_s3_bucket_public_access_block" "waf_logs_block" {
  bucket = aws_s3_bucket.waf_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}