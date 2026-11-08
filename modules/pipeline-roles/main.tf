module "policies" {
  source = "../deployment-policies"

  environment        = var.environment
  account_id         = var.account_id
  hub_account_id     = var.hub_account_id
  state_bucket       = var.state_bucket
  state_key_format   = var.state_key_format
  duties             = var.duties
  hub_segments       = var.hub_segments
  other_environments = var.other_environments
  github_repository  = var.github_repository
  branch             = var.branch
  github_oidc_host   = local.oidc_host
}

module "spoke_policies" {
  source   = "../deployment-policies"
  for_each = var.spokes

  environment       = each.key
  account_id        = each.value.account_id
  hub_account_id    = var.account_id
  state_bucket      = var.state_bucket
  state_key_format  = var.state_key_format
  duties            = {}
  hub_segments      = each.value.hub_segments
  github_repository = var.github_repository
  branch            = var.branch
  github_oidc_host  = local.oidc_host
}

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_oidc_provider ? 1 : 0

  url            = local.oidc_url
  client_id_list = ["sts.amazonaws.com"]

  tags = { Name = "${local.name_prefix}GitHub Actions" }
}

resource "aws_iam_policy" "read" {
  name        = "terraform-${var.environment}-read"
  description = "What every pipeline role of ${var.environment} may read: configuration, never the state bucket"
  policy      = local.policies["read"]

  tags = { Name = "${local.name_prefix}Terraform Read" }
}

resource "aws_iam_policy" "duty" {
  for_each = local.duty_policies

  name        = "terraform-${var.environment}-${each.key}"
  description = "${var.environment} ${each.value.duty} deployments${each.value.part == "" ? ": what they may change" : ", ${trimprefix(each.value.part, "-")}: what they may never do"}"
  policy      = local.policies[each.key]

  tags = { Name = "${local.name_prefix}Terraform ${title(each.value.duty)}${title(replace(each.value.part, "-", " "))}" }

  lifecycle {
    precondition {
      condition     = length(local.policies[each.key]) <= 6144
      error_message = "This policy is longer than the 6144 characters IAM allows a managed policy; with many environments, shorten their names or give some their own accounts."
    }
  }
}

resource "aws_iam_policy" "boundary" {
  for_each = var.duties

  name        = "terraform-boundary-${var.environment}-${each.key}"
  description = "The permission boundary of every role ${var.environment}'s ${each.key} stacks create: it can never reach the pipeline, the state, the organization or another environment"
  policy      = local.policies["boundary-${each.key}"]

  tags = { Name = "${local.name_prefix}Terraform Boundary ${title(each.key)}" }

  lifecycle {
    precondition {
      condition     = length(local.policies["boundary-${each.key}"]) <= 6144
      error_message = "This policy is longer than the 6144 characters IAM allows a managed policy; with many environments, shorten their names or give some their own accounts."
    }
  }
}

resource "aws_iam_role" "plan" {
  name                 = "terraform-plan-${var.environment}"
  description          = "Read-only plans of ${var.environment}, from pull requests and drift checks in ${var.github_repository}; no state lock, no stored plans, no secrets"
  assume_role_policy   = module.policies.trust["plan"]
  max_session_duration = 3600

  tags = { Name = "${local.name_prefix}Terraform Plan" }
}

resource "aws_iam_role_policy_attachment" "plan_read" {
  role       = aws_iam_role.plan.name
  policy_arn = aws_iam_policy.read.arn
}

resource "aws_iam_role_policy" "plan" {
  name   = "state-and-limits"
  role   = aws_iam_role.plan.id
  policy = local.policies["plan"]
}

resource "aws_iam_role" "propose" {
  name                 = "terraform-propose-${var.environment}"
  description          = "Plans of ${var.environment} proposed from ${var.branch} in ${var.github_repository}, with the state lock, stored for review"
  assume_role_policy   = module.policies.trust["propose"]
  max_session_duration = 3600

  tags = { Name = "${local.name_prefix}Terraform Propose" }
}

resource "aws_iam_role_policy_attachment" "propose_read" {
  role       = aws_iam_role.propose.name
  policy_arn = aws_iam_policy.read.arn
}

resource "aws_iam_role_policy" "propose" {
  name   = "state-and-limits"
  role   = aws_iam_role.propose.id
  policy = local.policies["propose"]
}

resource "aws_iam_role" "apply" {
  for_each = var.duties

  name                 = "terraform-apply-${var.environment}-${each.key}"
  description          = "Applies of approved ${var.environment} ${each.key} plans, only from the ${var.environment} GitHub environment of ${var.github_repository}"
  assume_role_policy   = module.policies.trust["apply"]
  max_session_duration = 7200

  tags = { Name = "${local.name_prefix}Terraform Apply ${title(each.key)}" }
}

resource "aws_iam_role_policy_attachment" "apply" {
  for_each = local.attachments

  role       = aws_iam_role.apply[each.value.duty].name
  policy_arn = each.value.policy == "read" ? aws_iam_policy.read.arn : aws_iam_policy.duty[each.value.policy].arn
}

resource "aws_iam_role" "network" {
  for_each = var.spokes

  name                 = "terraform-network-${each.key}"
  description          = "The hub's side of ${each.key}'s network: accepting its attachments, joining its own segment and announcing to the segments it may, and its private zones"
  assume_role_policy   = module.spoke_policies[each.key].network_trust
  max_session_duration = 3600

  tags = { Name = "${local.name_prefix}Terraform Network ${title(each.key)}" }
}

resource "aws_iam_role_policy" "network" {
  for_each = var.spokes

  name   = "hub-side-of-the-network"
  role   = aws_iam_role.network[each.key].id
  policy = module.spoke_policies[each.key].policies["network-role"]
}

resource "aws_iam_role" "dns_read" {
  for_each = var.spokes

  name                 = "terraform-dns-read-${each.key}"
  description          = "Reading the hub's zones when ${each.key} plans; the role that writes its names is only for applies"
  assume_role_policy   = module.spoke_policies[each.key].dns_read_trust
  max_session_duration = 3600

  tags = { Name = "${local.name_prefix}Terraform DNS Read ${title(each.key)}" }
}

resource "aws_iam_role_policy" "dns_read" {
  for_each = var.spokes

  name   = "read-the-zones"
  role   = aws_iam_role.dns_read[each.key].id
  policy = module.spoke_policies[each.key].policies["dns-read-role"]
}
