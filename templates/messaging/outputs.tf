output "queues" {
  description = "File name -> the queue's name, ARN, URL and dead-letter queue ARN."
  value       = { for name, q in module.sqs_queue : name => { name = q.name, arn = q.arn, url = q.url, dead_letter_arn = q.dead_letter_arn } }

  precondition {
    condition     = length(local.problems) == 0
    error_message = "The message files are not usable: ${join("; ", local.problems)}."
  }
}

output "topics" {
  description = "File name -> the topic's name and ARN."
  value       = { for name, t in module.sns_topic : name => { name = t.name, arn = t.arn } }
}
