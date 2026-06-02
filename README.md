# Dotfiles

Personal configuration files.

## Contents

- `.gitconfig` — Git configuration
- `.zshrc` — Zsh configuration (oh-my-zsh + powerlevel10k)
- `.zprofile` — Zsh profile
- `.bash_profile` — Bash profile
- `.vimrc` — Vim configuration
- `.config/nvim/` — Neovim configuration (NvChad v2.5 based)
- `bin/install-lsps` — install common language servers (Scala, Python, YAML, Go, Ruby, Java, Kotlin)
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
- Runs `bin/install-lsps` to install common language servers (Scala metals, pyright, yaml-language-server, gopls, solargraph + ruby-lsp, jdtls, kotlin-language-server)

## Language servers

`bin/install-lsps` is OS-aware (Homebrew on macOS, language-native installers on Linux) and idempotent — anything already on `PATH` is skipped.

```bash
install-lsps                # install all
install-lsps scala go ruby  # install only the listed langs
install-lsps --list         # show what's currently installed
```

## Manual Setup

```bash
git clone git@github.com:whitleykeith/dotfiles.git ~/dotfiles
cd ~/dotfiles && ./install.sh
```
