output "arns" {
  description = "Queue name -> ARN."
  value       = { for name, q in aws_sqs_queue.queues : name => q.arn }
}

output "urls" {
  description = "Queue name -> URL, which SDKs send to."
  value       = { for name, q in aws_sqs_queue.queues : name => q.url }
}
