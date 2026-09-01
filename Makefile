.PHONY: help lint fmt fmt-check verify-templates verify-templates-quick audit test test-bats ci diff apply doctor drift fix pre-commit-install

# Machine_type x arch matrix used by verify-templates.
MACHINE_TYPES := personal work
ARCHES := arm64 amd64

# Shared shell-tooling config (single source of truth). ShellCheck disables live in
# .shellcheckrc so they don't need repeating here.
SHFMT_FLAGS := -i 4 -ci -bn
SH_FILES := $(shell find . -type f \( -name '*.sh' -o -name 'executable_*' \) -not -path './.git/*')

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-25s\033[0m %s\n", $$1, $$2}'

lint: ## Run ShellCheck on all .sh, .sh.tmpl, executable_* files
	@echo "Running ShellCheck..."
	@find . -type f \( -name '*.sh' -o -name 'executable_*' \) -not -path './.git/*' | while read -r file; do \
		echo "  $$file"; \
		shellcheck -s bash "$$file"; \
	done
	@find . -name '*.sh.tmpl' -not -path './.git/*' | while read -r file; do \
		echo "  $$file (template)"; \
		scripts/strip-template-actions.sh "$$file" | shellcheck -s bash -; \
	done
	@echo "All ShellCheck checks passed."

fmt: ## Format shell scripts in place with shfmt
	@command -v shfmt >/dev/null 2>&1 || { echo "shfmt not installed: brew install shfmt"; exit 1; }
	@shfmt $(SHFMT_FLAGS) -w $(SH_FILES)

fmt-check: ## Verify shell scripts are formatted (shfmt -d)
	@command -v shfmt >/dev/null 2>&1 || { echo "shfmt not installed: brew install shfmt"; exit 1; }
	@echo "Running shfmt -d..."
	@shfmt $(SHFMT_FLAGS) -d $(SH_FILES)
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

# ggshield is deliberately absent here: `ggshield secret scan repo` bills the
# shared GitGuardian quota per commit scanned (~417 units on a 996-commit repo,
# out of a 10,000/30-day budget shared by every repo on this machine), and this
# target runs via `make ci` before every commit. ggshield coverage comes from
# the pre-push git hook (incremental, ~1 unit) and GitGuardian's GitHub App.
audit: ## Run secret scan (gitleaks) and brew bundle check
	@echo "Running gitleaks..."
	@if command -v gitleaks >/dev/null 2>&1; then \
		gitleaks detect --no-banner --source=. --config=.gitleaks.toml; \
	else \
		echo "  (gitleaks not installed — skipping)"; \
	fi
	@echo ""
	@echo "Running brew bundle check..."
	@if command -v brew >/dev/null 2>&1; then \
		chezmoi execute-template \
			--init --source="$$(pwd)" \
			--override-data '{"machine_type":"personal","gpg_signing_key":""}' \
			< Brewfile.tmpl | brew bundle check --no-upgrade --file=-; \
	else \
		echo "  (brew not available — skipping)"; \
	fi

pre-commit-install: ## Install pre-commit framework hooks for this repo
	@command -v pre-commit >/dev/null 2>&1 || { echo "pre-commit not installed: brew install pre-commit"; exit 1; }
	@pre-commit install --install-hooks
	@echo "Pre-commit hooks installed."

test: lint test-bats ## Run lint + bats unit tests + chezmoi doctor + chezmoi verify
	@echo ""
	@echo "Running chezmoi doctor..."
	@chezmoi doctor
	@echo ""
	@echo "Running chezmoi verify..."
	@chezmoi verify && echo "All targets match source." || echo "Drift detected -- run 'chezmoi diff' for details."

test-bats: ## Run bats-core unit tests under tests/ (no chezmoi/brew required)
	@command -v bats >/dev/null 2>&1 || { echo "bats not installed: brew install bats-core"; exit 1; }
	@echo "Running bats..."
	@bats tests/

ci: lint fmt-check verify-templates test-bats audit ## Umbrella target: everything CI runs (no apply/network)
	@echo ""
	@echo "All CI checks passed."

diff: ## Preview changes before applying
	@chezmoi diff

apply: ## Deploy changes to home directory (requires user confirmation in interactive sessions)
	@chezmoi apply

doctor: ## Run chezmoi health checks
	@chezmoi doctor

drift: ## Run a full drift check (chezmoi-drift-check --full); machine-only, not in CI
	@command -v chezmoi-drift-check >/dev/null 2>&1 || { echo "chezmoi-drift-check not on PATH; run 'chezmoi apply' first"; exit 1; }
	@chezmoi-drift-check --full

fix: ## Run the interactive remediation menu (chezmoi-fix); machine-only, not in CI
	@command -v chezmoi-fix >/dev/null 2>&1 || { echo "chezmoi-fix not on PATH; run 'chezmoi apply' first"; exit 1; }
	@chezmoi-fix
