# Who owns a shared application, if it already exists: read-only calls, at plan time. Anything but "does not exist" stops the
# plan with the reason, so a failed check is never taken for a missing application.
data "external" "ownership" {
  count = var.containerized ? 1 : 0

  program = ["bash", "-c", <<-EOT
    set -uo pipefail
    # The AWS CLI's credentials must be this stack's account: bin/tf sees to it; with plain terraform, export AWS_PROFILE.
    account=$(aws sts get-caller-identity --query Account --output text 2>&1) || { echo "the AWS CLI has no working credentials, to check who owns ${var.name}: $account" >&2; exit 1; }
    [ "$account" = "${var.account_id}" ] || { echo "the AWS CLI's credentials are for account $account, not ${var.account_id}: export AWS_PROFILE for this stack's account" >&2; exit 1; }
    if ! err=$(aws deploy get-application --application-name "${var.name}" --region "${var.region}" 2>&1 >/dev/null); then
      case "$err" in
        *ApplicationDoesNotExistException*) printf '{"exists":"false","owner":""}'; exit 0 ;;
        *) echo "could not check whether CodeDeploy application ${var.name} exists: $err" >&2; exit 1 ;;
      esac
    fi
    owner=$(aws deploy list-tags-for-resource --region "${var.region}" \
      --resource-arn "arn:aws:codedeploy:${var.region}:${var.account_id}:application:${var.name}" \
      --query "Tags[?Key=='EnvironmentOwner'].Value | [0]" --output text 2>&1) || { echo "could not read ${var.name}'s owner: $owner" >&2; exit 1; }
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

  depends_on = [aws_codedeploy_app.application]
}

# CodeDeploy's connection to GitHub is made by a first deployment from it. That deployment goes to a group of its own, which
# requires a tag no server carries, so it can never touch a server; it is started, then stopped. Only with a bootstrap set.
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

  tags = { Name = "${var.name}-connection-check", Application = var.name, GroupType = "connection-check" }

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
