module "iam_role" {
  source = "../../modules/iam-role"

  policies          = { for name, p in local.module_policies : name => p if length(local.problems) == 0 }
  roles             = { for name, r in local.module_roles : name => r if length(local.problems) == 0 }
  instance_profiles = { for name, f in local.profiles : name => tostring(f.role) if length(local.problems) == 0 }
}
