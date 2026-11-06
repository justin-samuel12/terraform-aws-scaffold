data "aws_vpc" "vpc" {
  tags = {
    Environment = var.environment
    Component   = "network"
  }
}

data "aws_ec2_managed_prefix_list" "lists" {
  for_each = local.list_names

  name = each.key
}

data "aws_security_group" "remote" {
  for_each = local.remote_names

  tags = {
    Environment = split("/", each.key)[0]
    Key         = split("/", each.key)[1]
  }
}
