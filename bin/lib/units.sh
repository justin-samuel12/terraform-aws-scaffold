CHECKED_DIR="${CHECKED_DIR:-${REPO_ROOT}/.terraform.d/checked}"

all_units() {
    local d
    for d in modules/*/ templates/*/ bootstrap/; do
        d="${d%/}"; ls "${d}"/tests/*.tftest.hcl >/dev/null 2>&1 && echo "test:${d}"
    done
    find live -mindepth 5 -maxdepth 5 -path '*/tests/*.tftest.hcl' -not -path 'live/common/*' -exec dirname {} \; | sed 's#/tests$##' | sort -u | sed 's#^#test:#'
    find live -mindepth 4 -maxdepth 4 -name main.tf -not -path 'live/common/*' | sed 's#^live/##; s#/main.tf$##' | sort | sed 's#^#files:#'
    find examples -mindepth 3 -maxdepth 3 -type d -not -path 'examples/config*' | sed 's#^examples/##' | sort | sed 's#^#example:#'
}

module_closure() {
    local queue=("$1") seen=" " d src target
    while [[ ${#queue[@]} -gt 0 ]]; do
        d="${queue[0]}"; queue=("${queue[@]:1}")
        [[ "${seen}" == *" ${d} "* ]] && continue
        seen+="${d} "; echo "${d}"
        for src in $(sed -n 's/^ *source *= *"\(\.[^"]*\)".*/\1/p' "${d}"/*.tf 2>/dev/null); do
            target="$(cd "${d}" && cd "${src}" 2>/dev/null && pwd -P)" || continue
            queue+=("${target#"${REPO_ROOT}"/}")
        done
    done
}

unit_inputs() {
    local kind="${1%%:*}" path="${1#*:}" component dirs=()
    case "${kind}" in
        test)
            dirs=($(module_closure "${path}"))
            [[ "${path}" == live/* ]] && dirs+=(live/common)
            dirs+=(tests/config tests/stacks tests/unset)
            [[ "${path}" == templates/compute ]] && dirs+=(blueprints/compute scripts)
            [[ "${path}" == templates/containers ]] && dirs+=(blueprints/containers)
            [[ "${path}" == templates/databases ]] && dirs+=(blueprints/databases) ;;
        files)
            component="${path##*/}"
            dirs=($(module_closure "live/${path}") live/common config tests/mock)
            [[ "${component}" == compute ]] && dirs+=(blueprints/compute scripts)
            [[ "${component}" == containers || "${component}" == databases ]] && dirs+=("blueprints/${component}")
            echo bin/check-files ;;
        example)
            component="${path##*/}"
            dirs=("examples/${path}" examples/config live/common tests/mock)
            [[ -d "templates/${component}" ]] && dirs+=($(module_closure "templates/${component}"))
            [[ "${component}" == compute ]] && dirs+=(blueprints/compute scripts)
            [[ "${component}" == containers || "${component}" == databases ]] && dirs+=("blueprints/${component}")
            printf '%s\n' bin/check-files bin/stack bin/backends ;;
    esac
    echo tests/lock/.terraform.lock.hcl
    find "${dirs[@]}" -type f -not -path '*/.terraform/*' -not -name '.terraform.lock.hcl' -not -name '*.tfstate*' 2>/dev/null
    [[ "${kind}" == files && -f "live/${path}/.terraform.lock.hcl" ]] && echo "live/${path}/.terraform.lock.hcl"
    return 0
}

fingerprint() {
    { echo "${TF_VERSION:-$(terraform version -json 2>/dev/null | jq -r .terraform_version)}"
      unit_inputs "$1" | sort -u | tr '\n' '\0' | xargs -0 shasum -a 256
    } | shasum -a 256 | cut -c1-64
}

checked_file() { echo "${CHECKED_DIR}/$(tr '/:' '%=' <<<"$1")"; }
passed_before() { [[ "$(cat "$(checked_file "$1")" 2>/dev/null)" == "$2" ]]; }
record_pass() { mkdir -p "${CHECKED_DIR}"; echo "$2" > "$(checked_file "$1")"; }
