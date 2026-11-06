REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
CONFIG_DIR="${CONFIG_DIR:-${REPO_ROOT}/config}"
MACHINE_CONFIG="${INFRA_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/infra/hashicorp-terraform.config}"
INTERACTIVE="${SETUP_INTERACTIVE:-$([[ -t 0 ]] && echo 1 || echo 0)}"

if [[ -t 1 ]]; then C_OK=$'\033[32m'; C_WARN=$'\033[33m'; C_BAD=$'\033[31m'; C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'; C_END=$'\033[0m'; else C_OK=""; C_WARN=""; C_BAD=""; C_DIM=""; C_BOLD=""; C_END=""; fi
ok()   { printf '  %s✓%s %s\n' "${C_OK}" "${C_END}" "$*"; }
warn() { printf '  %s!%s %s\n' "${C_WARN}" "${C_END}" "$*"; }
bad()  { printf '  %s✗%s %s\n' "${C_BAD}" "${C_END}" "$*"; }
todo() { printf '  %s·%s %s\n' "${C_DIM}" "${C_END}" "$*"; }
say()  { printf '  %s\n' "$*"; }
head1() { printf '\n%s%s%s\n' "${C_BOLD}" "$*" "${C_END}"; }

ask() {
    local answer
    read -r -p "  $1${2:+ [$2]}: " answer || true
    echo "${answer:-$2}"
}
ask_yes() { [[ "$(ask "$1 (y/n)" "$2")" =~ ^[Yy] ]]; }

region_files()   { local f; for f in "${CONFIG_DIR}"/*-*-[0-9].yml; do [[ -f "${f}" ]] && basename "${f}" .yml; done; }
primary_region() { local r; for r in $(region_files); do [[ "$(yq -r '.hub.primary // false' "${CONFIG_DIR}/${r}.yml")" == true ]] && { echo "${r}"; return; }; done; }
global_account() { yq -r '.account_id // ""' "${CONFIG_DIR}/global.yml" 2>/dev/null; }
environments() { local r; { echo shared; for r in $(region_files); do yq -r '.vpcs // {} | keys | .[]' "${CONFIG_DIR}/${r}.yml"; done; } | awk '!seen[$0]++'; }
account_for() {
    local env="$1" r a path
    [[ "${env}" == shared ]] && path='.hub.account_id' || path=".vpcs[\"${env}\"].account_id"
    for r in $(region_files); do
        a="$(yq -r "${path} // \"\"" "${CONFIG_DIR}/${r}.yml")"
        [[ -n "${a}" ]] && { echo "${a}"; return; }
    done
    global_account
}
profile_for() { [[ -f "${MACHINE_CONFIG}" ]] && yq -r ".profiles[\"$1\"] // \"\"" "${MACHINE_CONFIG}" 2>/dev/null || true; }
caller_account() { aws sts get-caller-identity ${1:+--profile "$1"} --query Account --output text 2>/dev/null || true; }

ip_plan_problems() {
    local dir="${1:-${CONFIG_DIR}}" out
    terraform -chdir="${REPO_ROOT}/modules/ip-plan" init -backend=false -input=false >/dev/null 2>&1 || { echo "the IP plan could not be loaded (terraform init in modules/ip-plan)"; return; }
    out="$(echo 'jsonencode(concat([for f in local.files.names : { rule = "names", where = f }], [for f in local.files.shape : { rule = "file_shape", where = f }], [for f in local.files.zones : { rule = "zones", where = f }], [for f in local.files.reserved : { rule = "reserved", where = f }], [for p in local.layout_problems : { rule = "layout", where = p }], flatten([for rule, keys in local.problems : [for k in keys : { rule = rule, where = try(local.labels[k], k) }]]), flatten([for rule, keys in local.conflicts : [for k in keys : { rule = "conflict_${rule}", where = try(local.labels[k], tostring(k), jsonencode(k)) }]])))' | terraform -chdir="${REPO_ROOT}/modules/ip-plan" console -no-color -var "config_path=${dir}" 2>&1)"
    local json
    json="$(grep -E '^"\[' <<<"${out}" | tail -n 1)"
    if [[ -z "${json}" ]]; then
        grep -q '^Error:' <<<"${out}" && echo "config/ could not be read: run terraform console in modules/ip-plan to see why"
        return 0
    fi
    jq -r 'fromjson | .[] | (
        {
          names: "region files are named after an AWS region",
          file_shape: "a region file has zones, hub and vpcs, and nothing else",
          zones: "zones are 2 to 6 zone IDs of one region, numbered az1 to az6",
          reserved: "shared is the hub environment, not a vpcs entry",
          layout: "",
          shape: "an unknown or misspelt key",
          cidr: "cidr is a network address: a /16 for a network, a /20 for a hub",
          segment: "segment is restricted, standard or shared",
          public: "public is true or false",
          asn: "amazon_side_asn is a private ASN, 64512 to 65534",
          primary: "primary is true or false",
          referencing: "security_group_referencing is true or false",
          conflict_account: "account_id differs between region files",
          conflict_team: "team differs between region files",
          conflict_primary: "exactly one hub has primary: true",
          conflict_asn_reused: "two hubs share an amazon_side_asn",
          conflict_outside: "a range outside 10.0.0.0/8",
          conflict_overlap: "two ranges overlap"
        }[.rule] // .rule) as $what
        | if $what == "" then .where else "\(.where): \($what)" end' <<<"${json}" | awk '!seen[$0]++'
}

hub_account_for() { local a; a="$(yq -r '.hub.account_id // ""' "${CONFIG_DIR}/$1.yml" 2>/dev/null)"; echo "${a:-$(global_account)}"; }
missing_account_stacks() {
    local r env acct hub
    for r in $(region_files); do
        hub="$(hub_account_for "${r}")"
        for env in $(yq -r '.vpcs // {} | keys | .[]' "${CONFIG_DIR}/${r}.yml"); do
            acct="$(account_for "${env}")"
            [[ -n "${acct}" && -n "${hub}" && "${acct}" != "${hub}" ]] || continue
            for c in logging session-manager; do [[ -f "${REPO_ROOT}/live/${r}/${env}/${c}/main.tf" ]] || echo "${r}/${env}/${c}"; done
            for c in baseline iam; do [[ -f "${REPO_ROOT}/live/global/${env}/${c}/main.tf" ]] || echo "global/${env}/${c}"; done
        done
    done | awk '!seen[$0]++'
}

zone_prefix() {
    local area dir num
    area="$(cut -d- -f1 <<<"$1")"; dir="$(cut -d- -f2 <<<"$1")"; num="$(cut -d- -f3 <<<"$1")"
    case "${dir}" in
        east) dir=e ;; west) dir=w ;; north) dir=n ;; south) dir=s ;; central) dir=c ;;
        northeast) dir=ne ;; northwest) dir=nw ;; southeast) dir=se ;; southwest) dir=sw ;;
    esac
    echo "${area}${dir}${num}"
}

ip_to_int() { local a b c d; IFS=. read -r a b c d <<<"$1"; echo $(( (a << 24) + (b << 16) + (c << 8) + d )); }
int_to_ip() { echo "$(( ($1 >> 24) & 255 )).$(( ($1 >> 16) & 255 )).$(( ($1 >> 8) & 255 )).$(( $1 & 255 ))"; }

slash16s() {
    local base bits n i start
    base="${1%/*}"; bits="${1#*/}"
    [[ "${bits}" -ge 8 && "${bits}" -le 16 ]] || return 1
    start=$(( $(ip_to_int "${base}") & ~((1 << (32 - bits)) - 1) ))
    n=$(( 1 << (16 - bits) ))
    for (( i = 0; i < n; i++ )); do echo "$(int_to_ip $(( start + (i << 16) )))/16"; done
}
