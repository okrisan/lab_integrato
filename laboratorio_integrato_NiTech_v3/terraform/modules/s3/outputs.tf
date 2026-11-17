# outputs.tf
output "tf_state_bucket_arn" { value = aws_s3_bucket.tf_state.arn }
output "waf_logs_bucket_id" { value = aws_s3_bucket.waf_logs.id }
output "waf_logs_bucket_arn" { value = aws_s3_bucket.waf_logs.arn }