.PHONY: help lint fmt fmt-check verify-templates verify-templates-quick audit test ci diff apply doctor pre-commit-install

# Machine_type x arch matrix used by verify-templates.
MACHINE_TYPES := personal work
ARCHES := arm64 amd64

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-25s\033[0m %s\n", $$1, $$2}'

lint: ## Run ShellCheck on all .sh, .sh.tmpl, executable_* files
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
	@echo "All ShellCheck checks passed."

fmt: ## Format shell scripts in place with shfmt
	@command -v shfmt >/dev/null 2>&1 || { echo "shfmt not installed: brew install shfmt"; exit 1; }
	@shfmt -i 4 -ci -bn -w $$(find . -type f \( -name '*.sh' -o -name 'executable_*' \) -not -path './.git/*')

fmt-check: ## Verify shell scripts are formatted (shfmt -d)
	@command -v shfmt >/dev/null 2>&1 || { echo "shfmt not installed: brew install shfmt"; exit 1; }
	@echo "Running shfmt -d..."
	@shfmt -i 4 -ci -bn -d $$(find . -type f \( -name '*.sh' -o -name 'executable_*' \) -not -path './.git/*')
	@echo "All files formatted correctly."

verify-templates-quick: ## Render every .tmpl once with default data (fast, used by pre-commit)
	@echo "Validating .tmpl files (single render)..."
	@failed=0; \
	for tmpl in $$(find . -name '*.tmpl' -not -path './.git/*' -not -name '.chezmoi.toml.tmpl'); do \
		printf "  %s\n" "$$tmpl"; \
		chezmoi execute-template \
			--init --source="$$(pwd)" \
			--override-data '{"machine_type":"personal","gpg_signing_key":"test"}' \
			< "$$tmpl" > /dev/null || { echo "    FAIL"; failed=1; }; \
	done; \
	exit $$failed

verify-templates: ## Render every .tmpl across the full machine_type x arch matrix
	@echo "Validating .tmpl files across $(MACHINE_TYPES) x $(ARCHES)..."
	@failed=0; \
	for tmpl in $$(find . -name '*.tmpl' -not -path './.git/*' -not -name '.chezmoi.toml.tmpl'); do \
		for mt in $(MACHINE_TYPES); do \
			for arch in $(ARCHES); do \
				printf "  %s [machine=%s arch=%s]\n" "$$tmpl" "$$mt" "$$arch"; \
				chezmoi execute-template \
					--init --source="$$(pwd)" \
					--override-data "{\"machine_type\":\"$$mt\",\"gpg_signing_key\":\"test\",\"chezmoi\":{\"arch\":\"$$arch\"}}" \
					< "$$tmpl" > /dev/null || { echo "    FAIL"; failed=1; }; \
			done; \
		done; \
	done; \
	exit $$failed

audit: ## Run secret scans (gitleaks + ggshield) and brew bundle check
	@echo "Running gitleaks..."
	@command -v gitleaks >/dev/null 2>&1 && gitleaks detect --no-banner --source=. --config=.gitleaks.toml || echo "  (gitleaks not installed — skipping)"
	@echo ""
	@echo "Running ggshield..."
	@command -v ggshield >/dev/null 2>&1 && ggshield secret scan repo . || echo "  (ggshield not installed — skipping)"
	@echo ""
	@echo "Running brew bundle check..."
	@command -v brew >/dev/null 2>&1 && chezmoi execute-template \
		--init --source="$$(pwd)" \
		--override-data '{"machine_type":"personal","gpg_signing_key":""}' \
		< Brewfile.tmpl | brew bundle check --no-upgrade --file=- || echo "  (brew not available — skipping)"

pre-commit-install: ## Install pre-commit framework hooks for this repo
	@command -v pre-commit >/dev/null 2>&1 || { echo "pre-commit not installed: brew install pre-commit"; exit 1; }
	@pre-commit install --install-hooks
	@echo "Pre-commit hooks installed."

test: lint ## Run lint + chezmoi doctor + chezmoi verify
	@echo ""
	@echo "Running chezmoi doctor..."
	@chezmoi doctor
	@echo ""
	@echo "Running chezmoi verify..."
	@chezmoi verify && echo "All targets match source." || echo "Drift detected -- run 'chezmoi diff' for details."

ci: lint fmt-check verify-templates audit ## Umbrella target: everything CI runs (no apply/network)
	@echo ""
	@echo "All CI checks passed."

diff: ## Preview changes before applying
	@chezmoi diff

apply: ## Deploy changes to home directory (requires user confirmation in interactive sessions)
	@chezmoi apply

doctor: ## Run chezmoi health checks
	@chezmoi doctor
