resource "aws_dynamodb_table" "results" {
  name         = "kube-montecarlo-jobs-results"
  billing_mode = "PAY_PER_REQUEST"

  # Primary key: job_id (backend writes job_id, worker writes result by job_id)
  hash_key = "job_id"

  attribute {
    name = "job_id"
    type = "S"
  }

  tags = {
    Project = "kube-montecarlo-jobs"
  }
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.results.name
  description = "DynamoDB table name for results lookup by job_id"
}

output "dynamodb_table_arn" {
  value       = aws_dynamodb_table.results.arn
  description = "DynamoDB table ARN"
}
