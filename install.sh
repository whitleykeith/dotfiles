#!/bin/bash
# install.sh — Codespaces dotfiles installer
# GitHub Codespaces clones this repo and runs this script automatically.
# See: https://docs.github.com/en/codespaces/setting-your-user-preferences/personalizing-github-codespaces-for-your-account#dotfiles

set -e

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "🔧 Installing dotfiles from $DOTFILES_DIR"

# ── Symlink shell dotfiles ──
for file in .zshrc .zprofile .bash_profile .gitconfig .vimrc; do
  src="$DOTFILES_DIR/$file"
  dest="$HOME/$file"
  if [ -f "$src" ]; then
    # Back up existing file if it's not already a symlink
    if [ -f "$dest" ] && [ ! -L "$dest" ]; then
      mv "$dest" "$dest.bak"
      echo "  Backed up existing $dest → $dest.bak"
    fi
    ln -sf "$src" "$dest"
    echo "  Linked $file"
  fi
done

# ── Symlink nvim config ──
if [ -d "$DOTFILES_DIR/.config/nvim" ]; then
  mkdir -p "$HOME/.config"
  if [ -d "$HOME/.config/nvim" ] && [ ! -L "$HOME/.config/nvim" ]; then
    mv "$HOME/.config/nvim" "$HOME/.config/nvim.bak"
    echo "  Backed up existing nvim config → nvim.bak"
  fi
  ln -sf "$DOTFILES_DIR/.config/nvim" "$HOME/.config/nvim"
  echo "  Linked .config/nvim"
fi

# ── Install tools commonly needed in codespaces ──

# Install neovim if not present
if ! command -v nvim &>/dev/null; then
  echo "  Installing neovim..."
  if command -v apt-get &>/dev/null; then
    sudo apt-get update -qq && sudo apt-get install -y -qq neovim >/dev/null 2>&1
  elif command -v brew &>/dev/null; then
    brew install neovim --quiet
  fi
  echo "  Installed neovim"
fi

# Set default shell to zsh if available
if command -v zsh &>/dev/null; then
  if [ "$SHELL" != "$(which zsh)" ]; then
    sudo chsh -s "$(which zsh)" "$(whoami)" 2>/dev/null || true
    echo "  Set default shell to zsh"
  fi
fi

# ── Git config for codespaces ──
# Codespaces sets CODESPACES=true in the environment
if [ "$CODESPACES" = "true" ]; then
  # Use GH CLI for credential management in codespaces
  git config --global credential.helper '!gh auth git-credential'
  echo "  Configured git credential helper for Codespaces"
fi

echo "✅ Dotfiles installed!"
