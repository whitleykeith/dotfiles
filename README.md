# Dotfiles

Personal configuration files.

## Contents

- `.gitconfig` — Git configuration
- `.zshrc` — Zsh configuration (oh-my-zsh + powerlevel10k)
- `.zprofile` — Zsh profile
- `.bash_profile` — Bash profile
- `.vimrc` — Vim configuration
- `.config/nvim/` — Neovim configuration (NvChad v2.5 based)
- `install.sh` — Automated setup script (used by Codespaces)

`install.sh` also clones [mattpocock/skills](https://github.com/mattpocock/skills) to `~/git/skills` and symlinks each skill into `~/.copilot/skills/` (skipping `deprecated` and `in-progress`). Rerun it to pick up upstream changes.

## GitHub Codespaces

This repo is set up for automatic personalization in [GitHub Codespaces](https://docs.github.com/en/codespaces/setting-your-user-preferences/personalizing-github-codespaces-for-your-account#dotfiles).

1. Go to [github.com/settings/codespaces](https://github.com/settings/codespaces)
2. Enable **"Automatically install dotfiles"**
3. Select `whitleykeith/dotfiles` as the repo

When a codespace starts, `install.sh` runs automatically and:
- Symlinks shell configs (`.zshrc`, `.gitconfig`, etc.) into `$HOME`
- Symlinks the nvim config into `~/.config/nvim`
- Installs neovim if not present
- Sets zsh as the default shell
- Configures git credential helper for Codespaces

## Manual Setup

```bash
git clone git@github.com:whitleykeith/dotfiles.git ~/dotfiles
cd ~/dotfiles && ./install.sh
```
