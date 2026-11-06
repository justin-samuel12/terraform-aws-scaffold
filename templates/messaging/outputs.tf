output "queues" {
  description = "File name -> the queue's name, ARN and URL."
  value       = { for name, full in local.queue_names : name => { name = full, arn = module.sqs_queue.arns[full], url = module.sqs_queue.urls[full] } if length(local.problems) == 0 }

  precondition {
    condition     = length(local.problems) == 0
    error_message = "The message files are not usable: ${join("; ", local.problems)}."
  }
}

output "topics" {
  description = "File name -> the topic's name and ARN."
  value       = { for name, t in module.sns_topic : name => { name = t.name, arn = t.arn } }
}
