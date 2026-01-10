resource "aws_sqs_queue" "jobs" {
  name = "kube-montecarlo-jobs-queue"

  # Worker can take time; visibility should cover typical processing time
  visibility_timeout_seconds = 300

  # Keep messages for 1 day
  message_retention_seconds = 86400

  # Long polling (reduces empty receives)
  receive_wait_time_seconds = 20

  tags = {
    Project = "kube-montecarlo-jobs"
  }
}

output "sqs_queue_url" {
  value       = aws_sqs_queue.jobs.id
  description = "SQS Queue URL for backend/worker"
}

output "sqs_queue_arn" {
  value       = aws_sqs_queue.jobs.arn
  description = "SQS Queue ARN"
}
