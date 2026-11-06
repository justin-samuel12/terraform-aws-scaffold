locals {
  environment_tag = try(data.aws_default_tags.current.tags["Environment"], "")
  name_prefix     = local.environment_tag == "" ? "" : "${title(local.environment_tag)} - "
  short_name      = trimprefix(var.name, "${local.environment_tag}-")

  statements = concat(
    [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.topic.arn
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }],
    [for s in var.policy_statements : merge(
      { Effect = s.effect, Action = s.actions, Resource = s.resources },
      length(s.principals) == 0 ? {} : { Principal = { for t in distinct([for p in s.principals : p.type]) : t => flatten([for p in s.principals : p.identifiers if p.type == t]) } },
      length(s.condition) == 0 ? {} : { Condition = { for test in distinct([for c in s.condition : c.test]) : test => { for c in s.condition : c.variable => c.values if c.test == test } } },
    )],
  )
}
