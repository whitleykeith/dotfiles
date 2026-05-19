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

# ── Install neovim (0.10+ required for NvChad / vim.uv) ──
install_neovim() {
  local NVIM_TAG="v0.11.0"
  local current=""

  if command -v nvim &>/dev/null; then
    current=$(nvim --version | head -1 | grep -oE '[0-9]+\.[0-9]+')
    if [ "$(echo "$current" | awk -F. '{print ($1 * 100) + $2}')" -ge 1100 ]; then
      echo "  Neovim $current already installed (>= 0.11)"
      return
    fi
    echo "  Neovim $current is too old, building from source..."
  else
    echo "  Installing neovim from source..."
  fi

  if command -v apt-get &>/dev/null; then
    sudo apt-get update -qq
    sudo apt-get install -y -qq ninja-build gettext cmake unzip curl build-essential >/dev/null 2>&1
    git clone --depth 1 --branch "$NVIM_TAG" https://github.com/neovim/neovim.git /tmp/neovim-build
    cd /tmp/neovim-build
    make CMAKE_BUILD_TYPE=Release -j"$(nproc)" >/dev/null 2>&1
    sudo make install >/dev/null 2>&1
    cd - >/dev/null
    rm -rf /tmp/neovim-build
  elif command -v brew &>/dev/null; then
    brew install neovim --quiet
  fi

  echo "  Installed $(nvim --version | head -1)"
}

install_neovim

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

# ── Custom scripts ──
if [ -d "$DOTFILES_DIR/bin" ]; then
  mkdir -p "$HOME/bin"
  for script in "$DOTFILES_DIR/bin/"*; do
    ln -sf "$script" "$HOME/bin/$(basename "$script")"
    echo "  Linked bin/$(basename "$script")"
  done
fi
