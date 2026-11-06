module "domain_join" {
  source = "../../modules/domain-join"

  environment  = var.environment
  associations = local.associations
}
