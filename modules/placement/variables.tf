variable "groups" {
  description = "Group name -> its settings as written in its file: count, server_name, tier, instance_type, and members (subnet_id, instance_type, and private_ip and secondary_private_ips, each a host number in the subnet or a full address)."
  type        = any
}

variable "network" {
  description = "This environment's VPC in this region, as the ip-plan module gives it: zones, subnets and reserved blocks per tier."
  type        = any
}

variable "label" {
  description = "Where the network is, for messages, such as \"operations's VPC in us-east-2\"."
  type        = string
}

variable "existing" {
  description = "Server name -> the Subnet tag (private-az2) of the server of that name that already exists, so it stays where it is. Empty on a first build."
  type        = map(string)
  default     = {}
}
