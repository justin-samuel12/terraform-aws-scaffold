output "zones" {
  description = "This environment's private zone: its name and id (null without a private domain)."
  value = {
    private = local.names.private == null ? null : { name = local.names.private, id = aws_route53_zone.private[0].zone_id }
  }

  precondition {
    condition     = length(local.regions) > 0
    error_message = "${var.environment} has no VPC in config/: its zones attach to its VPCs."
  }
}
