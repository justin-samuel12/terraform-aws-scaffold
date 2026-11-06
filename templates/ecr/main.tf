module "ip_plan" {
  source = "../../modules/ip-plan"

  config_path = var.config_path
}

module "ecr_repository" {
  source = "../../modules/ecr-repository"

  repositories              = local.ready ? local.built : {}
  replication_configuration = local.ready ? local.replication : null
}
