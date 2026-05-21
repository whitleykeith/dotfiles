if which pyenv > /dev/null; then eval "$(pyenv init -)"; fi

# Fix terminal key bindings (backspace, arrow keys) over SSH
export TERM=xterm-256color

# >>> coursier install directory >>>
export PATH="$PATH:/Users/whitleykeith/Library/Application Support/Coursier/bin"
# <<< coursier install directory <<<
