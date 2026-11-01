resource "aws_ec2_managed_prefix_list" "lists" {
  for_each = var.lists

  name           = each.key
  address_family = "IPv4"
  max_entries    = length(each.value) + var.headroom

  dynamic "entry" {
    for_each = each.value
    content {
      cidr        = entry.value.cidr
      description = entry.value.description
    }
  }

  tags = { Name = each.key }
}
