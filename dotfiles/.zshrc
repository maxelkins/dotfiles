
# Hide 'Last login' message
if [[ -n $SSH_TTY ]]; then
    :
else
    touch ~/.hushlogin
fi

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

ENABLE_CORRECTION="false"
COMPLETION_WAITING_DOTS="true"

# Plugins
plugins=(git)

source $ZSH/oh-my-zsh.sh

# Add Homebrew's executable directory to the front of the PATH
export PATH=/opt/homebrew/bin:$PATH
export HOMEBREW_NO_ENV_HINTS=1

# asdf condig
export PATH="${ASDF_DATA_DIR:-$HOME/.asdf}/shims:$PATH"

# Aliases
alias gl='git log --graph --oneline'
alias ga='git add .'
alias ll='ls -l'
alias dev='npm run dev'
alias ydev='yarn dev'
alias dcup='docker compose up'
alias dcdown='docker compose down'

# Ghostty config
# Add missing termifo https://ghostty.org/docs/help/terminfo
export TERM=xterm-256color

# -------
# Custom PS1
# -------
txtred='\033[0;31m'
bldpur='\033[1;35m'
txtgrn='\033[0;32m'
txtrst='\033[0m'

CUSTOM_HOST="max"

emojis=("👾" "🌐" "🎲" "🌍" "🔮" "🌵" "🙃" "🙌" "👀" "🚀" "🤯" "🤔" "🐸")
EMOJI=${emojis[$RANDOM % ${#emojis[@]}]}

print_before_the_prompt() {
    dir=${PWD/"$HOME"/"~"}
    printf "${txtred}%s: ${bldpur}%s ${txtgrn}%s\n${txtrst}" "$CUSTOM_HOST" "$dir"
}

precmd() { print_before_the_prompt }

setopt SHARE_HISTORY HIST_IGNORE_DUPS HIST_FIND_NO_DUPS

PS1="$EMOJI >"
