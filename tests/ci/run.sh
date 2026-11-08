#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${REPO_ROOT}"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
STACK=us-west-2/staging/compute
failures=0

pass() { echo "ok    $1"; }
fail() { echo "FAIL  $1"; failures=1; }
expect() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1: wanted '$3', got '$2'"; fi; }

has() { if grep -q -- "$2" "$3"; then pass "$1"; else fail "$1"; fi; }
lacks() { if grep -q -- "$2" "$3"; then fail "$1"; else pass "$1"; fi; }

mkdir -p "${WORK}/stub"
cat >"${WORK}/stub/make" <<'STUB'
#!/usr/bin/env bash
echo "make $* APPLY_CONFIRMED=${APPLY_CONFIRMED:-}" >>"${STUB_LOG}"
stack=""
for a in "$@"; do [[ "${a}" == STACK=* ]] && stack="${a#STACK=}"; done
for a in "$@"; do
    [[ "${a}" == plan && "${STUB_PLAN:-ok}" == fail ]] && { echo "Error: plan failed: details" >&2; echo '  │ local.secret is "hunter9"' >&2; exit 2; }
    [[ "${a}" == plan ]] && echo "  ~ password = \"hunter2\" -> \"hunter3\""
    if [[ "${a}" == plan ]]; then
        mkdir -p "live/${stack}/.terraform"
        printf '%s' "${STUB_PLAN_BYTES:-a plan}" >"live/${stack}/.terraform/plan.tfplan"
        echo "fingerprint 0" >"live/${stack}/.terraform/plan.fingerprint"
    fi
done
exit 0
STUB
cat >"${WORK}/stub/aws" <<'STUB'
#!/usr/bin/env bash
if [[ "$1" == sts ]]; then echo "${STUB_ACCOUNT:-}"; exit 0; fi
if [[ "$1" == ec2 ]]; then
    region=""; args=("$@")
    for i in "${!args[@]}"; do [[ "${args[$i]}" == --region ]] && region="${args[$((i + 1))]}"; done
    if [[ "${region}" != "${STUB_HUB_REGION:-}" ]]; then echo '{"TransitGateways": []}'; exit 0; fi
    cat "${STUB_EC2}/$2.json"; exit 0
fi
if [[ "$1" == s3api ]]; then
    key="" body="" conditional=0; shift 2
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --key) key="$2"; shift 2 ;;
            --body) body="$2"; shift 2 ;;
            --if-none-match) conditional=1; shift 2 ;;
            *) shift ;;
        esac
    done
    [[ "${conditional}" == 1 ]] || { echo "unconditional put" >&2; exit 1; }
    if [[ -e "${STUB_S3}/${key}" ]]; then echo "PreconditionFailed" >&2; exit 254; fi
    mkdir -p "$(dirname "${STUB_S3}/${key}")"; cp "${body}" "${STUB_S3}/${key}"; exit 0
fi
[[ "$1" == s3 ]] || exit 1
local_path() { if [[ "$1" == s3://* ]]; then local p="${1#s3://}"; echo "${STUB_S3}/${p#*/}"; else echo "$1"; fi; }
case "$2" in
    cp) src="$(local_path "$3")"; dst="$(local_path "$4")"; [[ -f "${src}" ]] || exit 1; mkdir -p "$(dirname "${dst}")"; cp "${src}" "${dst}" ;;
    rm) rm -f "$(local_path "$3")" ;;
    *) exit 1 ;;
esac
STUB
cat >"${WORK}/stub/terraform" <<'STUB'
#!/usr/bin/env bash
if [[ "$*" == *" show -json "* ]]; then
    echo '{"resource_changes":[{"address":"aws_db_instance.main","change":{"actions":["update"],"before":{"engine":"x","password":"hunter2"},"after":{"engine":"x","password":"hunter3"}}},{"address":"aws_instance.server","change":{"actions":["create"],"before":null,"after":{"ami":"ami-1"}}},{"address":"aws_vpc.same","change":{"actions":["no-op"]}}]}'
    exit 0
fi
if [[ "$*" == *" show "* ]]; then
    printf '  + a resource\n\n%s\n' "${STUB_SHOW}"
    exit 0
fi
exec "${REAL_TERRAFORM}" "$@"
STUB
cat >"${WORK}/stub/tf" <<'STUB'
#!/usr/bin/env bash
[[ "${STUB_STATE:-yes}" == yes && "$1" == *"${STUB_BUILT:-}"* ]] && echo aws_instance.server
exit 0
STUB
chmod +x "${WORK}"/stub/*
REAL_TERRAFORM="$(command -v terraform)"
export REAL_TERRAFORM STUB_LOG="${WORK}/log" STUB_S3="${WORK}/s3" BIN_TF="${WORK}/stub/tf" PATH="${WORK}/stub:${PATH}" INFRA_CONFIG=/nonexistent
unset GITHUB_TRIGGERING_ACTOR PIPELINE_TOKEN_FILE
export GITHUB_ACTOR=alice
: >"${STUB_LOG}"

changed() { printf '%s\n' "$1" >"${WORK}/files"; bin/ci changed --files "${WORK}/files"; }
all="$(find live -mindepth 4 -maxdepth 4 -name main.tf -not -path 'live/common/*' | wc -l | xargs)"
expect "a region's config reaches every stack" "$(changed config/us-west-2.yml | wc -l | xargs)" "${all}"
expect "no stack is listed twice" "$(changed config/us-west-2.yml | sort | uniq -d | wc -l | xargs)" 0
expect "a stack's file reaches only that stack" "$(changed "live/${STACK}/config/infra/sqlserver.yml")" "${STACK}"
expect "a doc reaches nothing" "$(changed docs/compute.md | wc -l | xargs)" 0
expect "a module reaches its callers" "$(changed modules/placement/locals.tf | grep -c '/compute$' | xargs)" "$(find live -path '*/compute/main.tf' -not -path '*/.terraform/*' | wc -l | xargs)"
first="$(changed config/us-west-2.yml | grep -n 'us-west-2/staging/network$' | cut -d: -f1)"
last="$(changed config/us-west-2.yml | grep -n 'us-west-2/staging/compute$' | cut -d: -f1)"
if (( first < last )); then pass "stacks come in apply order"; else fail "stacks come in apply order"; fi

STUB_SHOW="Plan: 2 to add, 0 to change, 0 to destroy." bin/ci plan "${WORK}/p1" "${STACK}" && rc=0 || rc=$?
expect "a plan with changes passes" "${rc}" 0
has "the report names the changes" 'changes | Plan: 2 to add' "${WORK}/p1/report.md"
has "a pull request plan takes no lock" '-lock=false' "${STUB_LOG}"
has "the report lists what changes" 'UPDATE  aws_db_instance.main  changes: password' "${WORK}/p1/report.md"
has "the report lists what is created" 'CREATE  aws_instance.server' "${WORK}/p1/report.md"
lacks "the report never shows a value" 'hunter' "${WORK}/p1/report.md"
lacks "unchanged resources are left out" 'aws_vpc.same' "${WORK}/p1/report.md"

STUB_PLAN=fail STUB_SHOW=x bin/ci plan "${WORK}/p2" "${STACK}" >/dev/null 2>&1 && rc=0 || rc=$?
expect "a failed plan fails" "${rc}" 1
has "a failed plan's log is in the report" 'plan failed: details' "${WORK}/p2/report.md"
lacks "but the values Terraform prints in an error are not" 'hunter9' "${WORK}/p2/report.md"

cat >"${WORK}/stub/order" <<'STUB'
#!/usr/bin/env bash
echo "not-applied us-west-2/staging/network"
STUB
chmod +x "${WORK}/stub/order"
: >"${STUB_LOG}"
BIN_ORDER="${WORK}/stub/order" STUB_SHOW=x bin/ci plan "${WORK}/p6" "${STACK}" && rc=0 || rc=$?
expect "a stack waiting on another is not a failure" "${rc}" 0
has "it is reported as blocked" 'blocked | needs us-west-2/staging/network' "${WORK}/p6/report.md"
lacks "it is not planned" ' plan ' "${STUB_LOG}"

bin/ci plan "${WORK}/p3" && rc=0 || rc=$?
expect "no stacks is a clean report" "${rc}" 0
bin/ci plan "${WORK}/p4" "not/a/stack" >/dev/null 2>&1 && rc=0 || rc=$?
expect "an unknown stack is refused" "${rc}" 2
bin/ci plan "${WORK}/p5" 'us-west-2/staging/compute;touch x' >/dev/null 2>&1 && rc=0 || rc=$?
expect "a stack with shell in it is refused" "${rc}" 2

sha() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
stored="${WORK}/s3/plans/${STACK}"
SHARED_STACK=us-east-2/shared/hub

: >"${STUB_LOG}"
STUB_PLAN_BYTES="plan one" STUB_SHOW="Plan: 2 to add, 0 to change, 0 to destroy." bin/ci propose "${STACK}" "${WORK}/a1" >/dev/null && rc=0 || rc=$?
expect "a proposal with changes passes" "${rc}" 0
digest="$(cat "${WORK}/a1/digest")"
printf '%s' "plan one" >"${WORK}/expected.tfplan"
expect "the digest is the plan file's SHA-256" "${digest}" "$(sha "${WORK}/expected.tfplan")"
if [[ -f "${stored}/${digest}.tfplan" && -f "${stored}/${digest}.fingerprint" && -f "${stored}/${digest}.json" ]]; then pass "the plan is stored under its digest"; else fail "the plan is stored under its digest"; fi
has "the report gives the digest to approve" "digest \`${digest}\`" "${WORK}/a1/report.md"
has "the report shows the plan's summary" 'Plan: 2 to add' "${WORK}/a1/report.md"
has "the report lists what changes" 'UPDATE  aws_db_instance.main  changes: password' "${WORK}/a1/report.md"
lacks "the report never shows a value" 'hunter' "${WORK}/a1/report.md"
has "the proposal records who proposed it" '"proposer": "alice"' "${stored}/${digest}.json"
has "the proposal records the region" '"region": "us-west-2"' "${stored}/${digest}.json"
has "the proposal records the environment" '"environment": "staging"' "${stored}/${digest}.json"
has "the proposal records when it expires" '"expires_at":' "${stored}/${digest}.json"
has "the public record holds the digest" "\"digest\": \"${digest}\"" "${WORK}/a1/public/proposal.json"
lacks "the public list never shows a value" 'hunter' "${WORK}/a1/public/changes.txt"
has "the proposal records the duty that applies it" '"duty": "workload"' "${stored}/${digest}.json"
if [[ -f "live/${STACK}/.terraform/plan.tfplan" ]]; then fail "no plan is left on the runner"; else pass "no plan is left on the runner"; fi
has "a proposal takes the lock" ' plan STACK' "${STUB_LOG}"
lacks "a proposal applies nothing" ' apply ' "${STUB_LOG}"

STUB_SHOW="No changes. Your infrastructure matches the configuration." bin/ci propose "${STACK}" "${WORK}/a2" >/dev/null && rc=0 || rc=$?
expect "a proposal with no changes passes" "${rc}" 0
if [[ -f "${WORK}/a2/digest" ]]; then fail "nothing is stored without changes"; else pass "nothing is stored without changes"; fi

: >"${STUB_LOG}"
bin/ci apply "${STACK}" "Plan: 2 to add, 0 to change, 0 to destroy." >/dev/null 2>&1 && rc=0 || rc=$?
expect "a summary line is not a digest" "${rc}" 2
bin/ci apply "${STACK}" "$(printf '0%.0s' {1..64})" >/dev/null 2>&1 && rc=0 || rc=$?
expect "an unknown digest is refused" "${rc}" 1
lacks "nothing was applied" ' apply ' "${STUB_LOG}"

cp "${stored}/${digest}.tfplan" "${WORK}/saved.tfplan"
printf '%s' "plan two" >"${stored}/${digest}.tfplan"
: >"${STUB_LOG}"
bin/ci apply "${STACK}" "${digest}" >/dev/null 2>&1 && rc=0 || rc=$?
expect "a stored plan that changed is refused" "${rc}" 1
lacks "the changed plan was not applied" ' apply ' "${STUB_LOG}"
cp "${WORK}/saved.tfplan" "${stored}/${digest}.tfplan"

mkdir -p "${WORK}/s3/plans/${SHARED_STACK}"
for ext in tfplan fingerprint json; do cp "${stored}/${digest}.${ext}" "${WORK}/s3/plans/${SHARED_STACK}/${digest}.${ext}"; done
: >"${STUB_LOG}"
GITHUB_ACTOR=bob bin/ci apply "${SHARED_STACK}" "${digest}" >/dev/null 2>&1 && rc=0 || rc=$?
expect "a plan proposed for another stack is refused" "${rc}" 1
lacks "it was not applied" ' apply ' "${STUB_LOG}"
rm -rf "${WORK}/s3/plans/${SHARED_STACK}"

: >"${STUB_LOG}"
DEPLOY_ENVIRONMENT=production bin/ci apply "${STACK}" "${digest}" >/dev/null 2>&1 && rc=0 || rc=$?
expect "a job approved for another environment is refused" "${rc}" 1
lacks "it was not applied" ' apply ' "${STUB_LOG}"

cp "${stored}/${digest}.json" "${WORK}/saved.json"
jq '.commit = "0000000000000000000000000000000000000000"' "${WORK}/saved.json" >"${stored}/${digest}.json"
bin/ci apply "${STACK}" "${digest}" >/dev/null 2>&1 && rc=0 || rc=$?
expect "a plan proposed from a commit not on the branch is refused" "${rc}" 1
lacks "it was not applied" ' apply ' "${STUB_LOG}"
cp "${WORK}/saved.json" "${stored}/${digest}.json"

for field in environment region duty account stack; do
    jq --arg f "${field}" '.[$f] = "tampered"' "${WORK}/saved.json" >"${stored}/${digest}.json"
    bin/ci apply "${STACK}" "${digest}" >/dev/null 2>&1 && rc=0 || rc=$?
    expect "a record naming another ${field} is refused" "${rc}" 1
done
jq '.digest = "0000"' "${WORK}/saved.json" >"${stored}/${digest}.json"
bin/ci apply "${STACK}" "${digest}" >/dev/null 2>&1 && rc=0 || rc=$?
expect "a record naming another digest is refused" "${rc}" 1
jq '.fingerprint = "0000"' "${WORK}/saved.json" >"${stored}/${digest}.json"
bin/ci apply "${STACK}" "${digest}" >/dev/null 2>&1 && rc=0 || rc=$?
expect "a replaced fingerprint is refused" "${rc}" 1
jq '.expires_at = 1' "${WORK}/saved.json" >"${stored}/${digest}.json"
bin/ci apply "${STACK}" "${digest}" >/dev/null 2>&1 && rc=0 || rc=$?
expect "an expired proposal is refused" "${rc}" 1
lacks "none of them was applied" ' apply ' "${STUB_LOG}"
cp "${WORK}/saved.json" "${stored}/${digest}.json"

mkdir -p "${WORK}/s3/applied/${STACK}"
echo claimed >"${WORK}/s3/applied/${STACK}/${digest}.json"
bin/ci apply "${STACK}" "${digest}" >/dev/null 2>&1 && rc=0 || rc=$?
expect "a plan another apply already claimed is refused" "${rc}" 1
lacks "it was not applied twice" ' apply ' "${STUB_LOG}"
rm "${WORK}/s3/applied/${STACK}/${digest}.json"

: >"${STUB_LOG}"
DEPLOY_ENVIRONMENT=staging bin/ci apply "${STACK}" "${digest}" >/dev/null 2>&1 && rc=0 || rc=$?
expect "the approved plan is applied" "${rc}" 0
has "apply is confirmed" 'apply .*APPLY_CONFIRMED=yes' "${STUB_LOG}"
has "the claim records the digest" "\"digest\": \"${digest}\"" "${WORK}/s3/applied/${STACK}/${digest}.json"
has "the result is recorded" '"exit_status": 0' "${WORK}/s3/applied/${STACK}/${digest}.result.json"
if [[ -e "${stored}/${digest}.tfplan" ]]; then fail "an applied plan is deleted"; else pass "an applied plan is deleted"; fi
if [[ -f "live/${STACK}/.terraform/plan.tfplan" ]]; then fail "no plan is left on the runner after apply"; else pass "no plan is left on the runner after apply"; fi
bin/ci apply "${STACK}" "${digest}" >/dev/null 2>&1 && rc=0 || rc=$?
expect "a plan applies once" "${rc}" 1

STUB_PLAN_BYTES="shared plan" STUB_SHOW="Plan: 1 to add, 0 to change, 0 to destroy." bin/ci propose "${SHARED_STACK}" "${WORK}/a3" >/dev/null
shared_digest="$(cat "${WORK}/a3/digest")"
: >"${STUB_LOG}"
bin/ci apply "${SHARED_STACK}" "${shared_digest}" >/dev/null 2>&1 && rc=0 || rc=$?
expect "the proposer cannot apply a shared plan" "${rc}" 1
lacks "it was not applied by them" ' apply ' "${STUB_LOG}"
STUB_PLAN_BYTES="shared plan again" STUB_SHOW="Plan: 1 to add, 0 to change, 0 to destroy." bin/ci propose "${SHARED_STACK}" "${WORK}/a4" >/dev/null
GITHUB_ACTOR=bob bin/ci apply "${SHARED_STACK}" "$(cat "${WORK}/a4/digest")" >/dev/null 2>&1 && rc=0 || rc=$?
expect "a second person applies it" "${rc}" 0
has "it was applied" 'apply .*APPLY_CONFIRMED=yes' "${STUB_LOG}"

cat >"${WORK}/stub/curl" <<'STUB'
#!/usr/bin/env bash
echo '{"value":"token-from-github"}'
STUB
chmod +x "${WORK}/stub/curl"
bin/ci credentials plan "${WORK}/c1" >/dev/null 2>&1 && rc=0 || rc=$?
expect "credentials need every environment's account" "${rc}" 1
CONFIG_DIR="${REPO_ROOT}/templates/pipeline/tests/own-accounts" bin/ci credentials plan "${WORK}/c2" >/dev/null 2>&1 && rc=0 || rc=$?
expect "credentials without a GitHub token are refused" "${rc}" 1
ACTIONS_ID_TOKEN_REQUEST_URL="https://example.invalid/token?x=1" ACTIONS_ID_TOKEN_REQUEST_TOKEN=t \
    CONFIG_DIR="${REPO_ROOT}/templates/pipeline/tests/own-accounts" bin/ci credentials plan "${WORK}/c3" >"${WORK}/c3.env" && rc=0 || rc=$?
expect "credentials from a GitHub token" "${rc}" 0
has "each environment assumes its own plan role in its own account" 'role_arn = arn:aws:iam::444444444444:role/terraform-plan-staging' "${WORK}/c3/aws-config"
has "the shared environment uses the hub account" 'role_arn = arn:aws:iam::111111111111:role/terraform-plan-shared' "${WORK}/c3/aws-config"
has "profiles are mapped as on a laptop" 'staging: pipeline-staging' "${WORK}/c3/machine.config"
has "the job's environment points at them" "^INFRA_CONFIG=${WORK}/c3/machine.config" "${WORK}/c3.env"
expect "the token is written for the AWS SDK" "$(cat "${WORK}/c3/token")" "token-from-github"
lacks "the token is never printed" 'token-from-github' "${WORK}/c3.env"
token() { ACTIONS_ID_TOKEN_REQUEST_URL="https://example.invalid/token?x=1" ACTIONS_ID_TOKEN_REQUEST_TOKEN=t CONFIG_DIR="${REPO_ROOT}/templates/pipeline/tests/own-accounts" "$@"; }
token bin/ci credentials propose "${WORK}/c5" >/dev/null
has "a proposal uses the propose roles" 'role/terraform-propose-production' "${WORK}/c5/aws-config"
lacks "a proposal gets no apply role" 'terraform-apply' "${WORK}/c5/aws-config"
has "planning reads the hub's zones through the read role" 'dns_read_only: true' "${WORK}/c5/machine.config"
token bin/ci credentials apply "${WORK}/c4" >/dev/null 2>&1 && rc=0 || rc=$?
expect "apply credentials are for one stack" "${rc}" 2
token bin/ci credentials apply "${WORK}/c6" "${STACK}" >/dev/null
lacks "an apply uses the role that writes names" 'dns_read_only' "${WORK}/c6/machine.config"
has "a workload stack gets only the workload role" 'role_arn = arn:aws:iam::444444444444:role/terraform-apply-staging-workload' "${WORK}/c6/aws-config"
expect "and only that role" "$(grep -c '^role_arn' "${WORK}/c6/aws-config" | xargs)" 1
lacks "a workload stack gets nothing in the hub" 'shared:' "${WORK}/c6/machine.config"
token bin/ci credentials apply "${WORK}/c7" us-west-2/staging/network >/dev/null
has "a network stack gets the network role" 'role_arn = arn:aws:iam::444444444444:role/terraform-apply-staging-network' "${WORK}/c7/aws-config"
has "and reaches the hub only through its own narrow role" 'role_arn = arn:aws:iam::111111111111:role/terraform-network-staging' "${WORK}/c7/aws-config"
has "which it assumes from the network role" 'source_profile = pipeline-staging' "${WORK}/c7/aws-config"
has "the hub provider uses it" 'shared: pipeline-hub' "${WORK}/c7/machine.config"
token bin/ci credentials apply "${WORK}/c8" us-east-2/shared/hub >/dev/null
has "the hub stack gets the hub role" 'role_arn = arn:aws:iam::111111111111:role/terraform-apply-shared-hub' "${WORK}/c8/aws-config"
token bin/ci credentials apply "${WORK}/c9" global/staging/pipeline >/dev/null 2>&1 && rc=0 || rc=$?
expect "the pipeline never applies its own roles" "${rc}" 1

STUB_BUILT="${STACK}" STUB_SHOW="Plan: 0 to add, 1 to change, 0 to destroy." bin/ci drift "${WORK}/d1" && rc=0 || rc=$?
expect "drift is not a failure" "${rc}" 0
if [[ -f "${WORK}/d1/drifted" ]]; then pass "drift is flagged"; else fail "drift is flagged"; fi
expect "only built stacks are planned" "$(grep -c '^| `' "${WORK}/d1/report.md" | xargs)" 1

STUB_BUILT="${STACK}" STUB_SHOW="No changes." bin/ci drift "${WORK}/d2" && rc=0 || rc=$?
expect "no drift passes" "${rc}" 0
if [[ -f "${WORK}/d2/drifted" ]]; then fail "no drift is not flagged"; else pass "no drift is not flagged"; fi

cat >"${WORK}/stub/gh" <<'STUB'
#!/usr/bin/env bash
[[ "$1" == api ]] || exit 1
shift
method=GET jqexpr="" path=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --method) method="$2"; shift 2 ;;
        --jq) jqexpr="$2"; shift 2 ;;
        --input) shift 2 ;;
        *) path="$1"; shift ;;
    esac
done
if [[ "${method}" != GET ]]; then echo "${method} ${path} $(jq -c .)" >>"${STUB_GH_LOG}"; echo "{}"; exit 0; fi
file="${STUB_GH}/$(tr '/' '_' <<<"${path}").json"
[[ -f "${file}" ]] || exit 1
if [[ -n "${jqexpr}" ]]; then jq -r "${jqexpr}" "${file}"; else cat "${file}"; fi
STUB
chmod +x "${WORK}/stub/gh"
export STUB_GH="${WORK}/gh" STUB_GH_LOG="${WORK}/gh.log"
mkdir -p "${STUB_GH}"; : >"${STUB_GH_LOG}"
GH_REPO_PATH="repos_example-org_infrastructure"
gh_config() { CONFIG_DIR="${REPO_ROOT}/templates/pipeline/tests/own-accounts" "$@"; }
gh_config bin/github plan >"${WORK}/gh-plan.txt"
has "the ruleset requires a fresh approval after every push" '"require_last_push_approval": true' "${WORK}/gh-plan.txt"
has "the ruleset dismisses approvals when the change moves" '"dismiss_stale_reviews_on_push": true' "${WORK}/gh-plan.txt"
has "the ruleset requires the code owners' review" '"require_code_owner_review": true' "${WORK}/gh-plan.txt"
has "nobody bypasses the ruleset" '"bypass_actors": \[\]' "${WORK}/gh-plan.txt"
has "each environment stops the person who started a run approving it" '"prevent_self_review": true' "${WORK}/gh-plan.txt"
has "tokens name the workflow file" '"job_workflow_ref"' "${WORK}/gh-plan.txt"
lacks "the plan comment is not a required check" '"context": "Plan"' "${WORK}/gh-plan.txt"
has "the token workflows get is read-only" '"default_workflow_permissions": "read"' "${WORK}/gh-plan.txt"

echo '[{"id": 7, "name": "infrastructure"}]' >"${STUB_GH}/${GH_REPO_PATH}_rulesets.json"
gh_config bin/github plan >/dev/null
jq -n --slurpfile r <(gh_config bin/github plan | sed -n '/^Ruleset on/,/^$/p' | sed '1d;$d') '$r[0] + {id: 7}' >"${STUB_GH}/${GH_REPO_PATH}_rulesets_7.json"
echo '{"default_workflow_permissions": "read", "can_approve_pull_request_reviews": false}' >"${STUB_GH}/${GH_REPO_PATH}_actions_permissions_workflow.json"
echo '{"use_default": false, "include_claim_keys": ["repo", "context", "job_workflow_ref"]}' >"${STUB_GH}/${GH_REPO_PATH}_actions_oidc_customization_sub.json"
echo '{"name": "plan", "deployment_branch_policy": {"custom_branch_policies": true}, "protection_rules": []}' >"${STUB_GH}/${GH_REPO_PATH}_environments_plan.json"
echo '{"branch_policies": [{"name": "main"}]}' >"${STUB_GH}/${GH_REPO_PATH}_environments_plan_deployment-branch-policies.json"
for env in shared operations production staging; do
    echo "{\"name\": \"${env}\", \"deployment_branch_policy\": {\"custom_branch_policies\": true}, \"protection_rules\": [{\"type\": \"required_reviewers\", \"prevent_self_review\": true, \"reviewers\": [{\"type\": \"User\"}]}]}" >"${STUB_GH}/${GH_REPO_PATH}_environments_${env}.json"
    echo '{"branch_policies": [{"name": "main"}]}' >"${STUB_GH}/${GH_REPO_PATH}_environments_${env}_deployment-branch-policies.json"
done
gh_config bin/github verify >"${WORK}/gh-verify.txt" 2>&1 && rc=0 || rc=$?
expect "settings that match pass verification" "${rc}" 0
echo '{"name": "production", "deployment_branch_policy": {"custom_branch_policies": true}, "protection_rules": [{"type": "required_reviewers", "prevent_self_review": false, "reviewers": [{"type": "User"}]}]}' >"${STUB_GH}/${GH_REPO_PATH}_environments_production.json"
gh_config bin/github verify >"${WORK}/gh-verify.txt" 2>&1 && rc=0 || rc=$?
expect "an environment whose proposer may approve fails verification" "${rc}" 1
has "and says what is wrong" 'the person who started a run cannot approve it: GitHub has false, wanted true' "${WORK}/gh-verify.txt"
jq '.rules |= map(if .type == "pull_request" then .parameters.require_last_push_approval = false else . end)' "${STUB_GH}/${GH_REPO_PATH}_rulesets_7.json" >"${WORK}/r.json" && mv "${WORK}/r.json" "${STUB_GH}/${GH_REPO_PATH}_rulesets_7.json"
gh_config bin/github verify >"${WORK}/gh-verify.txt" 2>&1 && rc=0 || rc=$?
has "a ruleset without fresh approvals fails verification" 'require_last_push_approval: GitHub has false, wanted true' "${WORK}/gh-verify.txt"
gh_config bin/github apply </dev/null >/dev/null 2>&1 && rc=0 || rc=$?
expect "apply asks before writing" "${rc}" 1
expect "and wrote nothing" "$(wc -l <"${STUB_GH_LOG}" | xargs)" 0
GITHUB_APPLY_CONFIRMED=yes gh_config bin/github apply >/dev/null 2>&1 || true
has "apply updates the existing ruleset" '^PUT repos/example-org/infrastructure/rulesets/7' "${STUB_GH_LOG}"
has "apply protects each environment" '^PUT repos/example-org/infrastructure/environments/production .*"prevent_self_review":true' "${STUB_GH_LOG}"

export GITHUB_REPOSITORY=example/repo
GH_PATH="repos_example_repo"
files() { printf '%s\n' "$1" >"${STUB_GH}/${GH_PATH}_pulls_7_files.json"; }
data() { bin/ci classify 7 "${WORK}/k" 2>&1; }
files '[{"status":"modified","filename":"config/us-west-2.yml"},{"status":"added","filename":"live/us-west-2/staging/compute/config/apps/new.yml"},{"status":"modified","filename":"blueprints/compute/versions.yml"}]'
expect "configuration alone is planned" "$(data)" "data_only=true"
for path in modules/vpc/main.tf live/us-west-2/staging/compute/main.tf .github/workflows/plan.yml bin/ci templates/duties.yml scripts/ubuntu.sh live/us-west-2/staging/compute/.terraform.lock.hcl config/../bin/x.yml live/us-west-2/staging/compute/backend.tf; do
    files "[{\"status\":\"modified\",\"filename\":\"config/global.yml\"},{\"status\":\"modified\",\"filename\":\"${path}\"}]"
    expect "with ${path} changed, nothing is planned with AWS access" "$(data)" "data_only=false"
done
files '[{"status":"renamed","filename":"config/a.yml","previous_filename":"bin/ci"}]'
expect "a file renamed out of code is not configuration" "$(data)" "data_only=false"

mkdir -p "${WORK}/repo/config" "${WORK}/head/config"
cp -R bin "${WORK}/repo/"
cp config/global.yml "${WORK}/repo/config/"
echo 'a: 1' >"${WORK}/repo/config/gone.yml"
echo 'b: 2' >"${WORK}/head/config/new.yml"
ln -s /etc/hosts "${WORK}/head/config/link.yml"
files '[{"status":"added","filename":"config/new.yml"},{"status":"removed","filename":"config/gone.yml"}]'
"${WORK}/repo/bin/ci" overlay 7 "${WORK}/head" "${WORK}/o1" && rc=0 || rc=$?
expect "the overlay takes configuration" "${rc}" 0
if [[ -f "${WORK}/repo/config/new.yml" && ! -e "${WORK}/repo/config/gone.yml" ]]; then pass "it adds and removes files"; else fail "it adds and removes files"; fi
files '[{"status":"added","filename":"config/link.yml"}]'
"${WORK}/repo/bin/ci" overlay 7 "${WORK}/head" "${WORK}/o2" >/dev/null 2>&1 && rc=0 || rc=$?
expect "a symlink from a pull request is refused" "${rc}" 1
cat >"${WORK}/head/config/evil.yml" <<'YAML'
vpcs:
  'a"]|error(strenv(ACTIONS_ID_TOKEN_REQUEST_TOKEN))|.["b':
    cidr: 10.0.0.0/16
YAML
files '[{"status":"added","filename":"config/evil.yml"}]'
"${WORK}/repo/bin/ci" overlay 7 "${WORK}/head" "${WORK}/o4" >/dev/null 2>&1 && rc=0 || rc=$?
expect "a key written to run as an expression is refused" "${rc}" 1
if [[ -e "${WORK}/repo/config/evil.yml" ]]; then fail "and is not copied"; else pass "and is not copied"; fi
mkdir -p "${WORK}/inj"
cat >"${WORK}/inj/us-east-1.yml" <<'YAML'
vpcs:
  'a"]|error(strenv(SECRET_VALUE))|.["b':
    account_id: "1"
  good:
    account_id: "111111111111"
YAML
expect "environment names from a file cannot carry an expression" "$(CONFIG_DIR="${WORK}/inj" bin/ci _environments 2>/dev/null | xargs)" "shared good"
files '[{"status":"modified","filename":"bin/ci"}]'
"${WORK}/repo/bin/ci" overlay 7 "${WORK}/head" "${WORK}/o3" >/dev/null 2>&1 && rc=0 || rc=$?
expect "code from a pull request is refused" "${rc}" 1

export GITHUB_ACTIONS=true GITHUB_RUN_ID=55
STUB_PLAN_BYTES="approved plan" STUB_SHOW="Plan: 1 to add, 0 to change, 0 to destroy." GITHUB_ACTIONS=false bin/ci propose "${SHARED_STACK}" "${WORK}/b1" >/dev/null
approved="$(cat "${WORK}/b1/digest")"
echo '[]' >"${STUB_GH}/${GH_PATH}_actions_runs_55_approvals.json"
: >"${STUB_LOG}"
GITHUB_ACTOR=bob bin/ci apply "${SHARED_STACK}" "${approved}" >/dev/null 2>&1 && rc=0 || rc=$?
expect "a run nobody approved is refused" "${rc}" 1
echo '[{"state":"approved","environments":[{"name":"staging"}],"user":{"login":"carol"}}]' >"${STUB_GH}/${GH_PATH}_actions_runs_55_approvals.json"
GITHUB_ACTOR=bob bin/ci apply "${SHARED_STACK}" "${approved}" >/dev/null 2>&1 && rc=0 || rc=$?
expect "an approval for another environment does not count" "${rc}" 1
echo '[{"state":"approved","environments":[{"name":"shared"}],"user":{"login":"alice"}}]' >"${STUB_GH}/${GH_PATH}_actions_runs_55_approvals.json"
GITHUB_ACTOR=bob bin/ci apply "${SHARED_STACK}" "${approved}" >/dev/null 2>&1 && rc=0 || rc=$?
expect "the proposer as the only approver of a shared plan is refused" "${rc}" 1
lacks "none of those applied" ' apply ' "${STUB_LOG}"
echo '[{"state":"approved","environments":[{"name":"shared"}],"user":{"login":"carol"}}]' >"${STUB_GH}/${GH_PATH}_actions_runs_55_approvals.json"
GITHUB_ACTOR=bob bin/ci apply "${SHARED_STACK}" "${approved}" >/dev/null 2>&1 && rc=0 || rc=$?
expect "a run approved by someone else applies" "${rc}" 0
has "the claim names who approved it" '"carol"' "${WORK}/s3/applied/${SHARED_STACK}/${approved}.json"
has "and who applied it" '"applied_by": "bob"' "${WORK}/s3/applied/${SHARED_STACK}/${approved}.json"
unset GITHUB_ACTIONS GITHUB_RUN_ID

mkdir -p "${WORK}/art"
now="$(date +%s)"
d64="$(printf 'a%.0s' {1..64})"
jq -n --arg d "${d64}" --arg s "${STACK}" --argjson e "$(( now + 600 ))" '{stack:$s,account:"444",region:"us-west-2",environment:"staging",duty:"workload",commit:"abc",digest:$d,proposer:"alice",expires_at:$e}' >"${WORK}/art/proposal.json"
echo 'UPDATE  aws_x.y  changes: z' >"${WORK}/art/changes.txt"
(cd "${WORK}/art" && zip -q ../art.zip proposal.json changes.txt)
cp "${WORK}/art.zip" "${STUB_GH}/${GH_PATH}_actions_artifacts_9_zip.json"
echo '{"artifacts":[{"id":9,"expired":false,"created_at":"2026-01-01","workflow_run":{"id":77}}]}' >"${STUB_GH}/${GH_PATH}_actions_artifacts?name=proposal-${d64}.json"
echo '{"path":".github/workflows/apply.yml","head_branch":"master","event":"workflow_dispatch","head_sha":"abc"}' >"${STUB_GH}/${GH_PATH}_actions_runs_77.json"
echo '{"status":"ahead"}' >"${STUB_GH}/${GH_PATH}_compare_abc...master.json"
bin/ci describe "${STACK}" "${d64}" "${WORK}/e1" && rc=0 || rc=$?
expect "the reviewer is shown the proposal" "${rc}" 0
has "with its account and digest" "${d64}" "${WORK}/e1/report.md"
has "and what changes" 'UPDATE  aws_x.y' "${WORK}/e1/report.md"
echo '{"path":".github/workflows/plan.yml","head_branch":"master","event":"pull_request"}' >"${STUB_GH}/${GH_PATH}_actions_runs_77.json"
bin/ci describe "${STACK}" "${d64}" "${WORK}/e2" >/dev/null 2>&1 && rc=0 || rc=$?
expect "an artifact from another workflow is refused" "${rc}" 1
echo '{"path":".github/workflows/apply.yml","head_branch":"topic","event":"workflow_dispatch"}' >"${STUB_GH}/${GH_PATH}_actions_runs_77.json"
bin/ci describe "${STACK}" "${d64}" "${WORK}/e3" >/dev/null 2>&1 && rc=0 || rc=$?
expect "an artifact from another branch is refused" "${rc}" 1
echo '{"path":".github/workflows/apply.yml","head_branch":"master","event":"workflow_dispatch","head_sha":"abc"}' >"${STUB_GH}/${GH_PATH}_actions_runs_77.json"
echo '{"status":"diverged"}' >"${STUB_GH}/${GH_PATH}_compare_abc...master.json"
bin/ci describe "${STACK}" "${d64}" "${WORK}/e4" >/dev/null 2>&1 && rc=0 || rc=$?
expect "an artifact from a tag named like the branch is refused" "${rc}" 1

export STUB_EC2="${WORK}/ec2" STUB_HUB_REGION=us-west-2
mkdir -p "${STUB_EC2}"
echo '{"TransitGateways":[{"TransitGatewayId":"tgw-1"}]}' >"${STUB_EC2}/describe-transit-gateways.json"
echo '{"TransitGatewayRouteTables":[{"TransitGatewayRouteTableId":"rt-s","Tags":[{"Key":"Segment","Value":"standard"}]},{"TransitGatewayRouteTableId":"rt-r","Tags":[{"Key":"Segment","Value":"restricted"}]}]}' >"${STUB_EC2}/describe-transit-gateway-route-tables.json"
attachment() { echo "{\"TransitGatewayAttachments\":[{\"TransitGatewayAttachmentId\":\"tgw-attach-1\",\"ResourceOwnerId\":\"$1\",\"Tags\":$2,\"Association\":{\"TransitGatewayRouteTableId\":\"$3\"}}]}" >"${STUB_EC2}/describe-transit-gateway-attachments.json"; }
propagates() { echo "{\"TransitGatewayAttachmentPropagations\":[{\"TransitGatewayRouteTableId\":\"$1\"}]}" >"${STUB_EC2}/get-transit-gateway-attachment-propagations.json"; }
audit() { CONFIG_DIR="${REPO_ROOT}/templates/pipeline/tests/own-accounts" bin/ci hub-audit "${WORK}/audit.txt" >/dev/null 2>&1; }
STAGING='[{"Key":"Environment","Value":"staging"}]'
attachment 444444444444 "${STAGING}" rt-s; propagates rt-s
audit && rc=0 || rc=$?
expect "an attachment where config/ puts it passes the audit" "${rc}" 0
attachment 999999999999 "${STAGING}" rt-s
audit && rc=0 || rc=$?
expect "an attachment from another account fails the audit" "${rc}" 1
has "and names the account" '999999999999' "${WORK}/audit.txt"
attachment 444444444444 '[]' rt-s
audit && rc=0 || rc=$?
expect "an unclaimed attachment fails the audit" "${rc}" 1
attachment 444444444444 "${STAGING}" rt-r
audit && rc=0 || rc=$?
expect "an attachment in another segment fails the audit" "${rc}" 1
attachment 444444444444 "${STAGING}" rt-s; propagates rt-r
audit && rc=0 || rc=$?
expect "an announcement into another segment fails the audit" "${rc}" 1

[[ "${failures}" == 0 ]]
