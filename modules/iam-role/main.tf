data "aws_partition" "current" {}

resource "aws_iam_role" "roles" {
  for_each = var.roles

  name                 = each.key
  description          = each.value.description
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = [for s in sort(tolist(each.value.services)) : "${s}.amazonaws.com"] }
    }]
  })

  tags = { Name = each.key }
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each = merge([for name, r in var.roles : { for p in r.managed_policies : "${name}/${p}" => { role = name, policy = p } }]...)

  role       = aws_iam_role.roles[each.value.role].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/${each.value.policy}"
}

# Shared policies, attached to every role that names them.
resource "aws_iam_policy" "policies" {
  for_each = var.policies

  name        = each.key
  description = each.value.description
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [for s in each.value.statements : merge({ Effect = s.effect, Action = s.actions, Resource = s.resources }, length(s.condition) == 0 ? {} : {
      Condition = { for test in distinct([for c in s.condition : c.test]) : test => { for c in s.condition : c.variable => c.values if c.test == test } }
    })]
  })

  tags = { Name = each.key }
}

resource "aws_iam_role_policy_attachment" "policies" {
  for_each = merge([for name, r in var.roles : { for p in r.policies : "${name}/${p}" => { role = name, policy = p } }]...)

  role       = aws_iam_role.roles[each.value.role].name
  policy_arn = aws_iam_policy.policies[each.value.policy].arn
}

resource "aws_iam_role_policy_attachment" "shared" {
  for_each = merge([for name, r in var.roles : { for i, arn in r.policy_arns : "${name}/${i}" => { role = name, arn = arn } }]...)

  role       = aws_iam_role.roles[each.value.role].name
  policy_arn = each.value.arn
}

resource "aws_iam_role_policy" "own" {
  for_each = { for name, r in var.roles : name => r if length(r.statements) > 0 }

  name = "${each.key}-policy"
  role = aws_iam_role.roles[each.key].name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [for s in each.value.statements : merge({ Effect = s.effect, Action = s.actions, Resource = s.resources }, length(s.condition) == 0 ? {} : {
      Condition = { for test in distinct([for c in s.condition : c.test]) : test => { for c in s.condition : c.variable => c.values if c.test == test } }
    })]
  })
}

# Instances take a role through an instance profile; a role EC2 may assume gets one.
resource "aws_iam_instance_profile" "profiles" {
  for_each = { for name, r in var.roles : name => r if contains(r.services, "ec2") }

  name = each.key
  role = aws_iam_role.roles[each.key].name

  tags = { Name = each.key }
}
