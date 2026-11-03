output "name" {
  description = "The queue's name, with .fifo when it is FIFO."
  value       = aws_sqs_queue.queue.name
}

output "arn" {
  description = "The queue's ARN."
  value       = aws_sqs_queue.queue.arn
}

output "url" {
  description = "The queue's URL, which SDKs send to."
  value       = aws_sqs_queue.queue.url
}

output "dead_letter_arn" {
  description = "The dead-letter queue's ARN, for alarms on messages arriving there."
  value       = aws_sqs_queue.dead_letter.arn
}
