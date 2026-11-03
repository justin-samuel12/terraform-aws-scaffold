output "name" {
  description = "The topic's name, with .fifo when it is FIFO."
  value       = aws_sns_topic.topic.name
}

output "arn" {
  description = "The topic's ARN, which publishers and alarms use."
  value       = aws_sns_topic.topic.arn
}
