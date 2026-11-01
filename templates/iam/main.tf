module "iam_role" {
  source = "../../modules/iam-role"

  policies = local.policies
  roles    = local.roles
}
