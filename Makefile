SHELL := /bin/bash
.DEFAULT_GOAL := help

REPO_ROOT     := $(shell pwd)
TARGET         = $(if $(findstring /,$(STACK)),$(STACK),$(if $(and $(REGION),$(ENV)),$(REGION)/$(ENV)$(if $(STACK),/$(STACK)),$(STACK)))
STACK_DIR      = live/$(TARGET)
EXAMPLE       := us-east-2/operations/network
STACKS        := $(sort $(patsubst %/main.tf,%,$(wildcard live/*/*/*/main.tf)))
JOBS          ?= 4
UNITS         := nice -n 10 bin/check-units --jobs $(JOBS) $(if $(CHANGED),--changed)
export TF_PLUGIN_CACHE_DIR ?= $(REPO_ROOT)/.terraform.d/plugin-cache

.PHONY: help setup status config bootstrap backends hooks stack init plan apply output validate security \
        order render check fmt fmt-check lint test validate-all check-files check-examples check-order diagram clean

define require_stack
	@test -n "$(TARGET)" || { echo "STACK is required, e.g. STACK=$(EXAMPLE), or REGION=us-east-2 ENV=operations STACK=network" >&2; exit 1; }
	@test -f "$(STACK_DIR)/main.tf" || { echo "no stack at $(STACK_DIR): use <region>/<environment>/<component>, or REGION, ENV and STACK together; create one with make stack" >&2; exit 1; }
endef

##@ First time, in this order

help: ## List targets
	@awk 'BEGIN {FS = ":.*## "} /^##@/ {printf "\n%s\n", substr($$0, 5)} /^[a-z-]+:.*## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo
	@echo "  STACK=<region>/<environment>/<component>, e.g. make plan STACK=$(EXAMPLE); make order also takes <region>/<environment>"
	@echo "  REGION= and ENV= with a short STACK, e.g. make plan REGION=us-east-2 ENV=operations STACK=network; make order takes REGION= and ENV= alone"
	@echo "  ARGS=  more for terraform plan, e.g. ARGS='-replace=<address>' to rebuild one server on purpose; apply runs that plan"
	@echo "  ONLY=  some stacks for check-files or check-examples, e.g. ONLY=\"us-east-2/operations/compute\""
	@echo "  CHANGED=1  skip whatever is unchanged since it last passed; JOBS=n  checks at a time (default 4)"

setup: ## Guided: accounts, regions, environments, IP scope; writes config/ and the stacks, then your profiles
	bin/setup

status: ## Where you are, from a fresh clone to a first plan, and the next command (read-only)
	bin/status

config: ## The whole configuration as tables: what is filled in, what to check, what is missing (read-only)
	bin/config

bootstrap: ## The state bucket: create it (asks first), finish a run that stopped, or use one that already exists
	bin/bootstrap

backends: ## Rewrite every stack's generated files: backend.tf, stack.tf and its copies of live/common
	bin/backends

hooks: ## Install the git hooks: format, lint, secrets and backends on every commit
	@test -d .git || { echo "not a git repository yet: git init first" >&2; exit 1; }
	cp .github/hooks/* .git/hooks/ && chmod +x .git/hooks/*

##@ One stack at a time (STACK=)

stack: ## Create a stack, calling templates/<component> when one exists
	@test -n "$(TARGET)" || { echo "STACK is required, e.g. STACK=$(EXAMPLE)" >&2; exit 1; }
	bin/stack $(TARGET)

init: ## Connect a stack to its state
	$(require_stack)
	bin/tf $(STACK_DIR) init -input=false

plan: ## Plan a stack and save the plan; read-only, but needs credentials and takes the state lock (ARGS= for more)
	$(require_stack)
	bin/tf $(STACK_DIR) plan -input=false $(ARGS)

apply: ## Apply the plan make plan saved, unchanged and recent, after asking
	$(require_stack)
	bin/tf $(STACK_DIR) apply -input=false

output: ## Show a stack's outputs
	$(require_stack)
	bin/tf $(STACK_DIR) output

order: ## The order to apply stacks in, and what is applied (STACK= an environment or one stack; read-only)
	bin/order $(TARGET)

render: ## Apps on blueprints: all of them, or APP=<app> across its environments (read-only)
	bin/render $(APP)

validate: ## Validate a stack without its backend
	$(require_stack)
	bin/tf $(STACK_DIR) init -backend=false -input=false >/dev/null
	bin/tf $(STACK_DIR) validate

##@ Checks: no credentials, no state

TRIVY_IMAGE ?= aquasec/trivy:0.63.0@sha256:6fb0646988fcd2fdf7bf123f7174945ebc2c9c72d1fa1567c8d7daeeb70f8037

check: fmt-check lint check-order ## Everything below, the slow parts side by side (CHANGED=1: only what changed since it passed)
	bin/backends --check
	$(UNITS)
	@echo "All checks passed."

fmt: ## Format every .tf file
	terraform fmt -recursive

fmt-check: ## Check formatting without changing files
	terraform fmt -recursive -check

lint: ## Lint every module, template and stack with tflint
	@command -v tflint >/dev/null || { echo "tflint is not installed -- docs/configuration.md" >&2; exit 1; }
	@stray=$$(for s in $(STACKS); do find $$s \( -name .terraform -o -name tests -o -name config \) -prune -o \( -name '*.yml' -o -name '*.yaml' \) -print; done); \
	  if [ -n "$$stray" ]; then echo "A stack's .yml files go in its config/ folder, never beside its .tf files or anywhere else:" >&2; echo "$$stray" | sed 's/^/  /' >&2; exit 1; fi
	@mixed=$$(find modules templates live -name main.tf -not -path '*/.terraform/*' -exec grep -l '^data "' {} +); \
	  if [ -n "$$mixed" ]; then echo "Data sources go in data.tf, never main.tf:" >&2; echo "$$mixed" | sed 's/^/  /' >&2; exit 1; fi
	@unbounded=$$(find modules templates -name '*.tf' -not -path '*/.terraform/*' -not -path '*/tests/*' -not -path 'modules/pipeline-roles/*' \
	    -exec awk '/^resource "aws_iam_role" /{inb=1; b=0; at=FILENAME":"FNR} inb && /permissions_boundary/{b=1} inb && /^}/{if(!b) print at; inb=0}' {} +); \
	  bounded=$$(grep -l '^variable "role_boundary"' modules/*/variables.tf | xargs -n1 dirname | xargs -n1 basename | paste -sd'|' -); \
	  uncalled=$$(find templates -name '*.tf' -not -path '*/.terraform/*' -not -path '*/tests/*' \
	    -exec awk -v m="$$bounded" '/^module "/{inm=1; hit=0; r=0; at=FILENAME":"FNR} inm && $$0 ~ "source *= *\"\\.\\./\\.\\./modules/(" m ")\"" {hit=1} inm && /role_boundary *=/{r=1} inm && /^}/{if(hit && !r) print at; inm=0}' {} +); \
	  if [ -n "$$unbounded$$uncalled" ]; then echo "Every IAM role a stack creates carries its duty's permission boundary (modules/role-boundary); these do not:" >&2; echo "$$unbounded $$uncalled" | tr ' ' '\n' | sed '/^$$/d; s/^/  /' >&2; exit 1; fi
	tflint --init >/dev/null
	tflint --recursive --format compact

test: ## Run every module's, template's and stack's tests against a mocked AWS (CHANGED=1, JOBS=n)
	$(UNITS) test

validate-all: ## Validate every stack without its backend
	@mkdir -p $(TF_PLUGIN_CACHE_DIR)
	@failed=0; for s in $(STACKS); do \
	  if ( cd $$s && terraform init -backend=false -input=false >/dev/null && terraform validate -no-color >/dev/null ); then echo "ok    $${s#live/}"; \
	  else echo "FAIL  $${s#live/}"; ( cd $$s && terraform validate -no-color ) | sed 's/^/      /'; failed=1; fi; \
	done; exit $$failed

check-files: ## Validate every stack, then plan its .yml files against a mocked AWS (ONLY= for some; CHANGED=1, JOBS=n)
	$(if $(ONLY),bin/check-files $(ONLY),$(UNITS) files)

check-examples: ## The same for examples/, each as make stack would create it (ONLY= for some; CHANGED=1, JOBS=n)
	$(if $(ONLY),bin/check-files --examples $(ONLY),$(UNITS) example)

security: ## Pinned security analysis: every pipeline policy linted (parliament) and modeled, and Terraform scanned (Trivy) on a clean copy
	bin/iam-check
	@command -v docker >/dev/null && docker info >/dev/null 2>&1 || { echo "Trivy runs from a pinned image: start Docker" >&2; exit 1; }
	@work=$$(mktemp -d); trap 'rm -rf "$$work"' EXIT; \
	  git ls-files -z --cached --others --exclude-standard | COPYFILE_DISABLE=1 tar --null -T - -cf - | tar -xf - -C "$$work"; \
	  mkdir -p "$${XDG_CACHE_HOME:-$$HOME/.cache}/infra-tools/trivy"; \
	  docker run --rm -v "$$work:/src:ro" -v "$${XDG_CACHE_HOME:-$$HOME/.cache}/infra-tools/trivy:/root/.cache" -w /src $(TRIVY_IMAGE) \
	    config --quiet --severity HIGH,CRITICAL --ignorefile .trivyignore.yml --exit-code 1 --format table . | grep -E '│ +[1-9]|CRITICAL|HIGH' || true; \
	  docker run --rm -v "$$work:/src:ro" -v "$${XDG_CACHE_HOME:-$$HOME/.cache}/infra-tools/trivy:/root/.cache" -w /src $(TRIVY_IMAGE) \
	    config --quiet --severity HIGH,CRITICAL --ignorefile .trivyignore.yml --exit-code 1 --format json . >/dev/null && echo "ok    Trivy: no high or critical finding beyond those in .trivyignore.yml"

check-order: ## Every template's lookups are in templates/needs.yml, and no stacks need each other in a loop (order_check: false turns it off)
	bin/order --check

diagram: ## Regenerate docs/diagram.md from config/ and live/
	bin/diagram

##@ Housekeeping

clean: ## Remove every .terraform folder and the provider cache (state is never local)
	find . -type d -name .terraform -prune -exec rm -rf {} +
	rm -rf .terraform.d .check-files
