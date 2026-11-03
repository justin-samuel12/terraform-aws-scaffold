# Who owns a shared application, if it already exists: read-only calls, at plan time, with the stack's credentials.
data "external" "ownership" {
  count = var.containerized ? 1 : 0

  program = ["bash", "-c", <<-EOT
    set -uo pipefail
    if ! aws deploy get-application --application-name "${var.name}" --region "${var.region}" >/dev/null 2>&1; then
      printf '{"exists":"false","owner":""}'
      exit 0
    fi
    owner=$(aws deploy list-tags-for-resource --region "${var.region}" \
      --resource-arn "arn:aws:codedeploy:${var.region}:${var.account_id}:application:${var.name}" \
      --query "Tags[?Key=='EnvironmentOwner'].Value | [0]" --output text 2>/dev/null) || owner=""
    [ "$owner" = "None" ] && owner=""
    printf '{"exists":"true","owner":"%s"}' "$owner"
  EOT
  ]
}

resource "aws_codedeploy_app" "application" {
  count = local.manage ? 1 : 0

  name             = var.name
  compute_platform = "Server"

  tags = merge({ Name = var.name }, var.containerized ? { EnvironmentOwner = var.environment } : {})
}

resource "aws_codedeploy_deployment_group" "groups" {
  for_each = toset(local.groups)

  app_name               = var.name
  deployment_group_name  = each.key
  service_role_arn       = var.service_role_arn
  deployment_config_name = var.deployment_config_name

  # Fixed servers: those declaring the application, in this environment, and carrying the selector tag if there is one.
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

  tags = { Name = "${var.name}-${each.key}", Application = var.name, GroupType = each.key }

  # The connection to GitHub is made by a first deployment; it is started and stopped at once, before any real one.
  provisioner "local-exec" {
    command = var.bootstrap == null || each.key != local.bootstrap_group ? "echo 'no CodeDeploy bootstrap for ${var.name}/${each.key}'" : <<-EOT
      id=$(aws deploy create-deployment --region "${var.region}" \
        --application-name "${var.name}" --deployment-group-name "${each.key}" \
        --deployment-config-name CodeDeployDefault.OneAtATime \
        --revision '{"revisionType":"GitHub","gitHubLocation":{"repository":"${try(var.bootstrap.repository, "")}","commitId":"${try(var.bootstrap.commit_id, "")}"}}' \
        --description "CodeDeploy connection setup; stopped at once" --query deploymentId --output text 2>&1) || true
      if [ -n "$id" ] && [ "$id" != "None" ]; then
        sleep 2
        aws deploy stop-deployment --region "${var.region}" --deployment-id "$id" >/dev/null 2>&1 || true
        echo "connection set up for ${var.name}/${each.key}"
      fi
    EOT
  }

  depends_on = [aws_codedeploy_app.application]
}
