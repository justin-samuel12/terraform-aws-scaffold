locals {
  config_dir   = coalesce(var.config_dir, path.root)
  files        = { for name in fileset(local.config_dir, "*.yml") : trimsuffix(name, ".yml") => yamldecode(file("${local.config_dir}/${name}")) }
  policy_files = { for name in fileset("${local.config_dir}/policies", "*.yml") : trimsuffix(name, ".yml") => yamldecode(file("${local.config_dir}/policies/${name}")) }

  # Built in: what every server needs for Session Manager, whatever its role is for. Sessions are encrypted with the sessions key
  # and streamed to /ssm/sessions; the agent does both with the server's own credentials -- docs/systems-manager.md. The key is
  # alias/shared-sessions in the hub account and alias/<environment>-sessions in an environment's own, so any *-sessions alias.
  builtin_policies = {
    session-manager = {
      description = "Session Manager on every server: decrypt with the sessions key, write session logs"
      statements = [
        {
          effect    = "Allow"
          actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
          resources = ["*"]
          condition = [{ test = "ForAnyValue:StringLike", variable = "kms:ResourceAliases", values = ["alias/*-sessions"] }]
        },
        {
          effect    = "Allow"
          actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
          resources = ["arn:aws:logs:*:*:log-group:/ssm/sessions:*"]
          condition = []
        },
        {
          effect    = "Allow"
          actions   = ["logs:DescribeLogGroups"]
          resources = ["*"]
          condition = []
        },
      ]
    }
  }

  file_policies = {
    for name, f in local.policy_files : name => {
      description = try(f.description, "")
      statements = [for s in try(f.statement, []) : {
        effect    = try(s.effect, "Allow")
        actions   = tolist(s.actions)
        resources = tolist(s.resources)
        condition = [for c in try(s.condition, []) : { test = c.test, variable = c.variable, values = [for v in c.values : tostring(v)] }]
      }]
    }
  }

  roles = {
    for name, f in local.files : name => {
      description      = try(f.description, "")
      services         = toset(try(f.services, []))
      managed_policies = try(tolist(f.managed_policies), [])
      policies         = concat(try(tolist(f.policies), []), contains(try(tolist(f.services), []), "ec2") ? ["session-manager"] : [])
      statements = [for s in try(f.statement, []) : {
        effect    = try(s.effect, "Allow")
        actions   = tolist(s.actions)
        resources = tolist(s.resources)
        condition = [for c in try(s.condition, []) : { test = c.test, variable = c.variable, values = [for v in c.values : tostring(v)] }]
      }]
    }
  }

  policies = merge(local.builtin_policies, local.file_policies)
}
