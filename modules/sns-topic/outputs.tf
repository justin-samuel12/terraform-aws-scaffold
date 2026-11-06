output "name" {
  description = "The topic's name."
  value       = aws_sns_topic.topic.name
}

output "arn" {
  description = "The topic's ARN, which publishers and alarms use."
  value       = aws_sns_topic.topic.arn
}
