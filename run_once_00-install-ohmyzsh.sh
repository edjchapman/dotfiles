#!/bin/bash
# Install oh-my-zsh if not present
# chezmoi run_once: only runs on first setup
# Runs BEFORE Homebrew (00 < 01) because .zshrc depends on oh-my-zsh

set -euo pipefail

if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    echo "Installing oh-my-zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
else
    echo "oh-my-zsh already installed."
fi
