data "aws_default_tags" "current" {}

data "external" "ownership" {
  count = var.containerized ? 1 : 0

  program = ["bash", "-c", <<-EOT
    set -uo pipefail
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
