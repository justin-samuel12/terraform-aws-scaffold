data "aws_sqs_queue" "queues" {
  for_each = { for name, queue in local.queue_names : name => queue if length(local.problems) == 0 }

  name = each.value
}

data "aws_sns_topic" "topics" {
  for_each = length(local.problems) == 0 ? local.topic_names : toset([])

  name = each.value
}

data "aws_vpc" "vpc" {
  count = length(local.problems) == 0 && length(local.vpc_configs) > 0 ? 1 : 0

  tags = {
    Environment = var.environment
    Component   = "network"
  }
}

data "aws_subnet" "subnets" {
  for_each = length(local.problems) == 0 ? local.subnets : toset([])

  vpc_id = data.aws_vpc.vpc[0].id
  tags   = { Subnet = each.key }
}

data "aws_security_group" "groups" {
  for_each = length(local.problems) == 0 ? local.groups : toset([])

  vpc_id = data.aws_vpc.vpc[0].id
  tags   = { Key = each.key }
}
