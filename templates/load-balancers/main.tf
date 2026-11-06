module "ip_plan" {
  source = "../../modules/ip-plan"

  config_path = var.config_path
}

module "load_balancer" {
  source   = "../../modules/load-balancer"
  for_each = { for name, lb in local.resolved : name => lb if length(local.problems) == 0 }

  name                  = "${var.environment}-${each.key}"
  load_balancer_type    = each.value.load_balancer_type
  internal              = each.value.internal
  vpc_id                = data.aws_vpc.vpc.id
  subnets               = each.value.subnets
  security_groups       = each.value.security_groups
  access_logs_bucket    = data.aws_s3_bucket.access_logs[0].id
  target_groups         = each.value.target_groups
  listeners             = each.value.listeners
  listener_rules        = each.value.listener_rules
  listener_certificates = each.value.listener_certificates
}
