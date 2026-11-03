# Thin entry point over bin/ and the tests -- docs/configuration.md.
SHELL := /bin/bash
.DEFAULT_GOAL := help

REPO_ROOT     := $(shell pwd)
STACK_DIR      = live/$(STACK)
EXAMPLE       := us-east-2/operations/network
STACKS        := $(sort $(patsubst %/main.tf,%,$(wildcard live/*/*/*/main.tf)))
JOBS          ?= 4
UNITS         := nice -n 10 bin/check-units --jobs $(JOBS) $(if $(CHANGED),--changed)
export TF_PLUGIN_CACHE_DIR ?= $(REPO_ROOT)/.terraform.d/plugin-cache

.PHONY: help setup status config bootstrap backends hooks stack init plan apply output validate \
        order render check fmt fmt-check lint test validate-all check-files check-examples check-order diagram clean

define require_stack
	@test -n "$(STACK)" || { echo "STACK is required, e.g. STACK=$(EXAMPLE)" >&2; exit 1; }
	@test -d "$(STACK_DIR)" || { echo "no stack at $(STACK_DIR); create it with make stack STACK=$(STACK)" >&2; exit 1; }
endef

##@ First time, in this order

help: ## List targets
	@awk 'BEGIN {FS = ":.*## "} /^##@/ {printf "\n%s\n", substr($$0, 5)} /^[a-z-]+:.*## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo
	@echo "  STACK=<region>/<environment>/<component>, e.g. make plan STACK=$(EXAMPLE); make order also takes <region>/<environment>"
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

backends: ## Rewrite every stack's backend.tf from config/global.yml
	bin/backends

hooks: ## Install the git hooks: format, lint, secrets and backends on every commit
	@test -d .git || { echo "not a git repository yet: git init first" >&2; exit 1; }
	cp .github/hooks/* .git/hooks/ && chmod +x .git/hooks/*

##@ One stack at a time (STACK=)

stack: ## Create a stack, calling templates/<component> when one exists
	@test -n "$(STACK)" || { echo "STACK is required, e.g. STACK=$(EXAMPLE)" >&2; exit 1; }
	bin/stack $(STACK)

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
	bin/order $(STACK)

render: ## Apps on blueprints: all of them, or APP=<app> across its environments (read-only)
	bin/render $(APP)

validate: ## Validate a stack without its backend
	$(require_stack)
	bin/tf $(STACK_DIR) init -backend=false -input=false >/dev/null
	bin/tf $(STACK_DIR) validate

##@ Checks: no credentials, no state

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

check-order: ## Every template's lookups are in templates/needs.yml, and no stacks need each other in a loop (order_check: false turns it off)
	bin/order --check

diagram: ## Regenerate docs/diagram.md from config/ and live/
	bin/diagram

##@ Housekeeping

clean: ## Remove every .terraform folder and the provider cache (state is never local)
	find . -type d -name .terraform -prune -exec rm -rf {} +
	rm -rf .terraform.d .check-files
