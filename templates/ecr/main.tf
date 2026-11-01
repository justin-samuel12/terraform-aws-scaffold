module "ip_plan" {
  source = "../../modules/ip-plan"

  config_path = var.config_path
}

module "ecr_repository" {
  source = "../../modules/ecr-repository"

  repositories  = local.repositories
  keep_images   = local.settings.keep_images
  untagged_days = local.settings.untagged_days
  replicate_to  = local.replicate_to
}
