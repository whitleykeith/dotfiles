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
  local NVIM_VERSION="v0.11.0"

  if command -v nvim &>/dev/null; then
    local major minor
    major=$(nvim --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | cut -d. -f1)
    minor=$(nvim --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | cut -d. -f2)
    if [ "$major" -ge 1 ] || { [ "$major" -eq 0 ] && [ "$minor" -ge 11 ]; }; then
      echo "  Neovim ${major}.${minor} already installed (>= 0.11)"
      return
    fi
    echo "  Neovim ${major}.${minor} is too old, upgrading..."
    sudo rm -f "$(which nvim)"
    sudo apt-get remove -y neovim neovim-runtime 2>/dev/null || true
  else
    echo "  Installing neovim..."
  fi

  # Try prebuilt tarball first (fastest, requires GLIBC 2.34+)
  curl -sL "https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/nvim-linux-x86_64.tar.gz" | sudo tar xz -C /opt
  if /opt/nvim-linux-x86_64/bin/nvim --version &>/dev/null; then
    sudo ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim
  else
    # GLIBC too old for prebuilt binary — build from source
    echo "  Prebuilt binary incompatible with this GLIBC, building from source..."
    sudo rm -rf /opt/nvim-linux-x86_64
    sudo apt-get update -qq
    sudo apt-get install -y -qq ninja-build gettext cmake unzip curl build-essential >/dev/null 2>&1
    curl -sL "https://github.com/neovim/neovim/archive/refs/tags/${NVIM_VERSION}.tar.gz" | tar xz -C /tmp
    cd /tmp/neovim-${NVIM_VERSION#v}
    make CMAKE_BUILD_TYPE=Release -j"$(nproc)" >/dev/null 2>&1
    sudo make install >/dev/null 2>&1
    cd - >/dev/null
    rm -rf "/tmp/neovim-${NVIM_VERSION#v}"
  fi

  echo "  Installed $(nvim --version | head -1)"
}

install_neovim

# Install and set zsh as default shell
if ! command -v zsh &>/dev/null; then
  echo "  Installing zsh..."
  sudo apt-get update -qq && sudo apt-get install -y -qq zsh >/dev/null 2>&1
fi
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
