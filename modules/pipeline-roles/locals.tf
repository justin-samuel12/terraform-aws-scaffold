locals {
  oidc_host    = "token.actions.githubusercontent.com"
  oidc_url     = "https://${local.oidc_host}"
  provider_arn = var.create_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
  name_prefix  = "${title(var.environment)} - "
  policies     = module.policies.policies

  duty_policies = merge([
    for duty in keys(var.duties) : {
      for part in ["", "-state", "-limits", "-environment", "-ownership"] : "${duty}${part}" => { duty = duty, part = part }
    }
  ]...)
  attachments = merge([
    for duty in keys(var.duties) : {
      for policy in concat(["read"], [for part in ["", "-state", "-limits", "-environment", "-ownership"] : "${duty}${part}"]) : "${duty}/${policy}" => { duty = duty, policy = policy }
    }
  ]...)
}
