resource "aws_codedeploy_app" "application" {
  count = local.manage ? 1 : 0

  name             = var.name
  compute_platform = "Server"

  tags = merge({ Name = "${local.name_prefix}${var.name}" }, var.containerized ? { EnvironmentOwner = var.environment } : {})
}

resource "aws_codedeploy_deployment_group" "groups" {
  for_each = toset(local.groups)

  app_name               = var.name
  deployment_group_name  = each.key
  service_role_arn       = var.service_role_arn
  deployment_config_name = var.deployment_config_name

  ec2_tag_set {
    ec2_tag_filter {
      key  = "CodeDeploy:${var.name}"
      type = "KEY_ONLY"
    }
  }

  ec2_tag_set {
    ec2_tag_filter {
      key   = "Environment"
      type  = "KEY_AND_VALUE"
      value = var.environment
    }
  }

  dynamic "ec2_tag_set" {
    for_each = var.selector == null ? [] : [var.selector]
    content {
      ec2_tag_filter {
        key   = ec2_tag_set.value.key
        type  = "KEY_AND_VALUE"
        value = ec2_tag_set.value.value
      }
    }
  }

  autoscaling_groups = var.autoscaling_groups

  auto_rollback_configuration {
    enabled = length(var.rollback_events) > 0
    events  = var.rollback_events
  }

  deployment_style {
    deployment_type   = "IN_PLACE"
    deployment_option = local.traffic_control ? "WITH_TRAFFIC_CONTROL" : "WITHOUT_TRAFFIC_CONTROL"
  }

  dynamic "load_balancer_info" {
    for_each = local.traffic_control ? [1] : []
    content {
      dynamic "target_group_info" {
        for_each = toset(var.target_group_names)
        content {
          name = target_group_info.value
        }
      }
    }
  }

  tags = { Name = "${local.name_prefix}${var.name}-${each.key}", Application = var.name, GroupType = each.key }

  depends_on = [aws_codedeploy_app.application]
}

resource "aws_codedeploy_deployment_group" "connection" {
  count = var.bootstrap == null ? 0 : 1

  app_name              = var.name
  deployment_group_name = "connection-check"
  service_role_arn      = var.service_role_arn

  ec2_tag_set {
    ec2_tag_filter {
      key  = "CodeDeploy:${var.name}"
      type = "KEY_ONLY"
    }
  }

  ec2_tag_set {
    ec2_tag_filter {
      key  = "CodeDeployConnectionCheck"
      type = "KEY_ONLY"
    }
  }

  tags = { Name = "${local.name_prefix}${var.name}-connection-check", Application = var.name, GroupType = "connection-check" }

  provisioner "local-exec" {
    command = <<-EOT
      if ! id=$(aws deploy create-deployment --region "${var.region}" \
          --application-name "${var.name}" --deployment-group-name connection-check \
          --revision '{"revisionType":"GitHub","gitHubLocation":{"repository":"${try(var.bootstrap.repository, "")}","commitId":"${try(var.bootstrap.commit_id, "")}"}}' \
          --description "CodeDeploy's GitHub connection; a group with no servers" --query deploymentId --output text); then
        echo "CodeDeploy could not start the connection deployment for ${var.name} (above); its GitHub connection is not set up yet." >&2
        exit 0
      fi
      case "$id" in
        d-*) aws deploy stop-deployment --region "${var.region}" --deployment-id "$id" >/dev/null 2>&1 || true
             echo "CodeDeploy's GitHub connection set up for ${var.name} (deployment $id, to no servers, stopped)." ;;
        *)   echo "CodeDeploy returned no deployment for ${var.name}: '$id'; its GitHub connection is not set up yet." >&2 ;;
      esac
    EOT
  }

  depends_on = [aws_codedeploy_app.application]
}
