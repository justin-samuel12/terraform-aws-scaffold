output "servers" {
  description = "Server name -> its instance id and private address."
  value       = { for name, i in aws_instance.servers : name => { id = i.id, private_ip = i.private_ip } }
}
