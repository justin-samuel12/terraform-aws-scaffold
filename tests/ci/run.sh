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
for a in "$@"; do
    [[ "${a}" == plan && "${STUB_PLAN:-ok}" == fail ]] && { echo "plan failed: details"; exit 2; }
done
exit 0
STUB
cat >"${WORK}/stub/terraform" <<'STUB'
#!/usr/bin/env bash
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
export REAL_TERRAFORM STUB_LOG="${WORK}/log" BIN_TF="${WORK}/stub/tf" PATH="${WORK}/stub:${PATH}"
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

STUB_PLAN=fail STUB_SHOW=x bin/ci plan "${WORK}/p2" "${STACK}" >/dev/null 2>&1 && rc=0 || rc=$?
expect "a failed plan fails" "${rc}" 1
has "a failed plan's log is in the report" 'plan failed: details' "${WORK}/p2/report.md"

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

: >"${STUB_LOG}"
STUB_SHOW="Plan: 2 to add, 0 to change, 0 to destroy." bin/ci apply "${STACK}" "Plan: 1 to add, 0 to change, 0 to destroy." >/dev/null 2>&1 && rc=0 || rc=$?
expect "apply refuses a plan it was not told to expect" "${rc}" 1
lacks "nothing was applied" ' apply ' "${STUB_LOG}"

: >"${STUB_LOG}"
STUB_SHOW="Plan: 2 to add, 0 to change, 0 to destroy." bin/ci apply "${STACK}" "Plan: 2 to add, 0 to change, 0 to destroy." >/dev/null 2>&1 && rc=0 || rc=$?
expect "apply runs the plan it expected" "${rc}" 0
has "apply is confirmed" 'apply .*APPLY_CONFIRMED=yes' "${STUB_LOG}"
if [[ "$(grep -c -- '-lock=false' "${STUB_LOG}" || true)" == 0 ]]; then pass "apply takes the lock"; else fail "apply takes the lock"; fi

: >"${STUB_LOG}"
STUB_SHOW="No changes. Your infrastructure matches the configuration." bin/ci apply "${STACK}" "Plan: 2 to add, 0 to change, 0 to destroy." >/dev/null 2>&1 && rc=0 || rc=$?
expect "apply with no changes succeeds" "${rc}" 0
lacks "no changes applies nothing" ' apply ' "${STUB_LOG}"

STUB_BUILT="${STACK}" STUB_SHOW="Plan: 0 to add, 1 to change, 0 to destroy." bin/ci drift "${WORK}/d1" && rc=0 || rc=$?
expect "drift is not a failure" "${rc}" 0
if [[ -f "${WORK}/d1/drifted" ]]; then pass "drift is flagged"; else fail "drift is flagged"; fi
expect "only built stacks are planned" "$(grep -c '^| `' "${WORK}/d1/report.md" | xargs)" 1

STUB_BUILT="${STACK}" STUB_SHOW="No changes." bin/ci drift "${WORK}/d2" && rc=0 || rc=$?
expect "no drift passes" "${rc}" 0
if [[ -f "${WORK}/d2/drifted" ]]; then fail "no drift is not flagged"; else pass "no drift is not flagged"; fi

[[ "${failures}" == 0 ]]
