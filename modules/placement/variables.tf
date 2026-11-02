variable "groups" {
  description = "Group name -> its settings as written in its file: count, tier, instance_type, and members (subnet, ip or ips, type)."
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
