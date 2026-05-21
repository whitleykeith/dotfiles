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
  # Fetch latest stable release tag from GitHub API
  local NVIM_VERSION
  NVIM_VERSION=$(curl -sL https://api.github.com/repos/neovim/neovim/releases/latest | grep -oP '"tag_name":\s*"\K[^"]+')
  echo "  Latest neovim release: ${NVIM_VERSION}"

  if command -v nvim &>/dev/null; then
    local current
    current=$(nvim --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    if [ "v${current}" = "${NVIM_VERSION}" ]; then
      echo "  Neovim ${current} already installed (latest)"
      return
    fi
    echo "  Neovim ${current} installed, upgrading to ${NVIM_VERSION}..."
    sudo rm -f "$(which nvim)"
    sudo apt-get remove -y neovim neovim-runtime 2>/dev/null || true
  else
    echo "  Installing neovim ${NVIM_VERSION}..."
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

# ── Install Node.js/npm if not present (needed for LSP servers) ──
if ! command -v npm &>/dev/null; then
  echo "  Installing Node.js..."
  curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - >/dev/null 2>&1
  sudo apt-get install -y -qq nodejs >/dev/null 2>&1
fi

# ── Install LSP servers (only when their runtime is available) ──
if command -v npm &>/dev/null; then
  echo "  Installing npm-based LSP servers..."
  npm install -g yaml-language-server typescript typescript-language-server bash-language-server vscode-langservers-extracted @tailwindcss/language-server 2>/dev/null || true
fi

if command -v pip3 &>/dev/null; then
  echo "  Installing Python LSP servers..."
  pip3 install --user pyright 2>/dev/null || true
fi

if command -v go &>/dev/null; then
  echo "  Installing Go LSP servers..."
  go install golang.org/x/tools/gopls@latest 2>/dev/null || true
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
