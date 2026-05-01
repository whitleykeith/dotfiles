# Dotfiles

Personal configuration files.

## Contents

- `.gitconfig` — Git configuration
- `.zshrc` — Zsh configuration (oh-my-zsh + powerlevel10k)
- `.zprofile` — Zsh profile
- `.bash_profile` — Bash profile
- `.vimrc` — Vim configuration
- `.config/nvim/` — Neovim configuration (NvChad v2.5 based)

## Setup

```bash
# Clone
git clone git@github.com:whitleykeith/dotfiles.git ~/dotfiles

# Symlink what you need
ln -sf ~/dotfiles/.gitconfig ~/.gitconfig
ln -sf ~/dotfiles/.zshrc ~/.zshrc
ln -sf ~/dotfiles/.vimrc ~/.vimrc
ln -sf ~/dotfiles/.config/nvim ~/.config/nvim
```

> **Note:** Some values are placeholder-scrubbed (e.g., `<YOUR_EMAIL>`). Update them for your environment.
