.PHONY: lint test diff apply doctor help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

lint: ## Run ShellCheck on all scripts
	@echo "Running ShellCheck..."
	@find . -name '*.sh' -not -path './.git/*' | while read -r file; do \
		echo "  $$file"; \
		shellcheck -s bash -e SC1071,SC2086 "$$file"; \
	done
	@find . -name '*.sh.tmpl' -not -path './.git/*' | while read -r file; do \
		echo "  $$file (template)"; \
		sed -E 's/\{\{.*\}\}//g' "$$file" | shellcheck -s bash -e SC1071,SC2086 -; \
	done
	@find . -name 'executable_*' -not -path './.git/*' | while read -r file; do \
		echo "  $$file"; \
		shellcheck -s bash -e SC1071,SC2086 "$$file"; \
	done
	@echo "All checks passed."

test: lint ## Run all validations (lint + chezmoi doctor)
	@echo ""
	@echo "Running chezmoi doctor..."
	@chezmoi doctor
	@echo ""
	@echo "Running chezmoi verify..."
	@chezmoi verify && echo "All targets match source." || echo "Drift detected -- run 'chezmoi diff' for details."

diff: ## Preview changes before applying
	@chezmoi diff

apply: ## Deploy changes to home directory
	@chezmoi apply

doctor: ## Run chezmoi health checks
	@chezmoi doctor