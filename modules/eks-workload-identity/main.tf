resource "aws_iam_role" "roles" {
  for_each = var.roles

  name                 = each.key
  description          = each.value.description
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Principal = { Service = "pods.eks.amazonaws.com" }
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.account_id }
        ArnEquals    = { "aws:SourceArn" = var.cluster_arn }
      }
    }]
  })

  tags = { Name = "${local.name_prefix}${trimprefix(each.key, "${local.environment_tag}-")}" }
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each = merge([for name, r in var.roles : { for p in r.policy_arns : "${name} ${p}" => { role = name, policy_arn = p } }]...)

  role       = aws_iam_role.roles[each.value.role].name
  policy_arn = each.value.policy_arn
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

resource "aws_eks_pod_identity_association" "associations" {
  for_each = var.roles

  cluster_name    = var.cluster_name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = aws_iam_role.roles[each.key].arn

  tags = { Name = "${local.name_prefix}${trimprefix(each.key, "${local.environment_tag}-")}" }

  depends_on = [aws_iam_role_policy_attachment.managed, aws_iam_role_policy.own]
}
