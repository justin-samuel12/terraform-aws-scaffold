# Thin entry point over bin/ and the tests -- docs/configuration.md.
SHELL := /bin/bash
.DEFAULT_GOAL := help

REPO_ROOT := $(shell pwd)
STACK_DIR  = live/$(STACK)
EXAMPLE   := us-east-1/development/network
MODULES   := $(sort $(dir $(wildcard modules/*/versions.tf templates/*/versions.tf bootstrap/versions.tf)))
STACKS    := $(sort $(patsubst %/main.tf,%,$(wildcard live/*/*/*/main.tf)))
STACKS_TESTED := $(sort $(patsubst %/tests/,%/,$(dir $(wildcard live/*/*/*/tests/*.tftest.hcl))))
export TF_PLUGIN_CACHE_DIR ?= $(REPO_ROOT)/.terraform.d/plugin-cache

.PHONY: help setup bootstrap backends hooks stack init plan apply output validate \
        check fmt fmt-check lint test validate-all check-files diagram clean

define require_stack
	@test -n "$(STACK)" || { echo "STACK is required, e.g. STACK=$(EXAMPLE)" >&2; exit 1; }
	@test -d "$(STACK_DIR)" || { echo "no stack at $(STACK_DIR); create it with make stack STACK=$(STACK)" >&2; exit 1; }
endef

##@ First time, in this order

help: ## List targets
	@awk 'BEGIN {FS = ":.*## "} /^##@/ {printf "\n%s\n", substr($$0, 5)} /^[a-z-]+:.*## / {printf "  %-13s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo
	@echo "  STACK=<region>/<environment>/<component>, e.g. make plan STACK=$(EXAMPLE)"

setup: ## Check prerequisites, then choose this machine's AWS profile for each environment
	bin/setup

bootstrap: ## Create the state bucket (asks first), move its state into it, write backends
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

plan: ## Plan a stack: read-only, but needs credentials and takes the state lock
	$(require_stack)
	bin/tf $(STACK_DIR) plan -input=false

apply: ## Apply a stack, after showing the plan and asking
	$(require_stack)
	bin/tf $(STACK_DIR) apply -input=false

output: ## Show a stack's outputs
	$(require_stack)
	bin/tf $(STACK_DIR) output

validate: ## Validate a stack without its backend
	$(require_stack)
	bin/tf $(STACK_DIR) init -backend=false -input=false >/dev/null
	bin/tf $(STACK_DIR) validate

##@ Checks: no credentials, no state

check: fmt-check lint test validate-all check-files ## All of the checks below, as CI would run them
	bin/backends --check
	@echo "All checks passed."

fmt: ## Format every .tf file
	terraform fmt -recursive

fmt-check: ## Check formatting without changing files
	terraform fmt -recursive -check

lint: ## Lint every module, template and stack with tflint
	@command -v tflint >/dev/null || { echo "tflint is not installed -- docs/configuration.md" >&2; exit 1; }
	tflint --init >/dev/null
	tflint --recursive --format compact

test: ## Run every module's, template's and stack's tests against a mocked AWS
	@mkdir -p $(TF_PLUGIN_CACHE_DIR)
	@for m in $(MODULES) $(STACKS_TESTED); do \
	  echo "== $$m"; \
	  ( cd $$m && terraform init -backend=false -input=false >/dev/null && terraform test ) || exit 1; \
	done

validate-all: ## Validate every stack without its backend
	@mkdir -p $(TF_PLUGIN_CACHE_DIR)
	@failed=0; for s in $(STACKS); do \
	  if ( cd $$s && terraform init -backend=false -input=false >/dev/null && terraform validate -no-color >/dev/null ); then echo "ok    $${s#live/}"; \
	  else echo "FAIL  $${s#live/}"; ( cd $$s && terraform validate -no-color ) | sed 's/^/      /'; failed=1; fi; \
	done; exit $$failed

check-files: ## Plan every stack's .yml files against a mocked AWS (or ONLY="<stack> ...")
	bin/check-files $(ONLY)

diagram: ## Regenerate docs/diagram.md from config/ and live/
	bin/diagram

##@ Housekeeping

clean: ## Remove every .terraform folder and the provider cache (state is never local)
	find . -type d -name .terraform -prune -exec rm -rf {} +
	rm -rf .terraform.d
