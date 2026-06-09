if which pyenv > /dev/null; then eval "$(pyenv init -)"; fi

# Fix terminal key bindings (backspace, arrow keys) over SSH
export TERM=xterm-256color

# >>> coursier install directory >>>
export PATH="$PATH:/Users/whitleykeith/Library/Application Support/Coursier/bin"
# <<< coursier install directory <<<

#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"
