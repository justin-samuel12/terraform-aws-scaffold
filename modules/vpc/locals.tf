locals {
  # "<tier>-<zone>" -> one subnet; every subnet gets its own route table.
  subnets = merge([
    for tier, subnet in var.subnets : {
      for index, zone in var.availability_zone_ids : "${tier}-${zone}" => {
        tier          = tier
        zone          = zone
        cidr          = subnet.cidrs[index]
        default_route = subnet.default_route
        reserved      = try(subnet.reserved_cidrs[index], null)
      }
    }
  ]...)

  transit_routes = merge([
    for tier, subnet in var.subnets : {
      for pair in setproduct(var.availability_zone_ids, subnet.transit_routes) :
      "${tier}-${pair[0]}-${pair[1]}" => { subnet = "${tier}-${pair[0]}", destination = pair[1] }
    }
  ]...)

  internet_gateway = anytrue([for subnet in var.subnets : subnet.default_route == "internet"])
  nat_gateways     = var.nat_gateway_subnets == null ? toset([]) : toset(var.availability_zone_ids)

  # Only VPC Flow Logs, acting for this account's flow logs, may take the role.
  flow_log_assume_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Condition = {
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:aws:ec2:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:vpc-flow-log/*" }
      }
    }]
  })

  flow_log_write_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
      Resource = "${aws_cloudwatch_log_group.flow_log.arn}:*"
    }]
  })
}
