eval "$(/opt/homebrew/bin/brew shellenv)"

# Setting PATH for Python 3.10
# The original version is saved in .zprofile.pysave
PATH="/Library/Frameworks/Python.framework/Versions/3.10/bin:${PATH}"
export PATH

# >>> coursier install directory >>>
export PATH="$PATH:/Users/whitleykeith/Library/Application Support/Coursier/bin"
# <<< coursier install directory <<<
