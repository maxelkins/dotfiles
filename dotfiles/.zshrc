# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME=""

ENABLE_CORRECTION="false"

# Uncomment the following line to display red dots whilst waiting for completion.
COMPLETION_WAITING_DOTS="true"

# Plugins
plugins=(git)

fpath=(/opt/homebrew/opt/asdf/share/zsh/site-functions $fpath)

source $ZSH/oh-my-zsh.sh

# User configuration

# Add Homebrew's executable directory to the front of the PATH
export PATH=/opt/homebrew/bin:$PATH
export HOMEBREW_NO_ENV_HINTS=1

# Aliases

alias gl='git log --graph --oneline'
alias ga='git add .'
alias ll='ls -l'
alias dev='npm run dev'
alias ydev='yarn dev'
alias dcup='docker compose up'
alias dcdown='docker compose down'
alias dup="colima start --cpu 4 --memory 8"
alias ddown="colima stop"
alias opr='op run --'

# ccusage AI usage
ai-today() { npx ccusage daily --compact -s "$(date +%Y-%m-%d)" -u "$(date +%Y-%m-%d)" }
ai-week() { npx ccusage daily --compact -s "$(date -v-$(( $(date +%u) - 1 ))d +%Y-%m-%d)" -u "$(date +%Y-%m-%d)" }
ai-month() { npx ccusage daily --compact -s "$(date +%Y-%m-01)" -u "$(date +%Y-%m-%d)" }
ai-last-week() { npx ccusage daily --compact -s "$(date -v-$(( $(date +%u) + 6 ))d +%Y-%m-%d)" -u "$(date -v-$(date +%u)d +%Y-%m-%d)" }
ai-last-month() { npx ccusage daily --compact -s "$(date -v-1m +%Y-%m-01)" -u "$(date -v1d -v-1d +%Y-%m-%d)" }

# Editor ansible playbooks (run in the current dir)
export EDITOR_PLAYBOOKS="$HOME/dev/ansible-playbooks/local/editor"
alias editor-setup='ansible-playbook "$EDITOR_PLAYBOOKS/setup_editor.yml"'
alias editor-up='ansible-playbook "$EDITOR_PLAYBOOKS/start_editor.yml"'
alias editor-down='ansible-playbook "$EDITOR_PLAYBOOKS/stop_editor.yml"'
alias editor-cleanup='ansible-playbook "$EDITOR_PLAYBOOKS/cleanup_editor.yml"'

## asdf config

export PATH="/opt/homebrew/opt/asdf/bin:$HOME/.asdf/shims:$PATH"

# Added by LM Studio CLI (lms)
export PATH="$PATH:/Users/max.elkins/.lmstudio/bin"

# 1password tokens
# export GITHUB_TOKEN="$(op read 'op://Employee/GITHUB_TOKEN/credential')"
# export GITHUB_TOKEN="op://Employee/GITHUB_TOKEN/credential"
# export NPM_AUTH_TOKEN=$GITHUB_TOKEN


# Enable history sharing between sessions (zsh equivalent of bash history commands)
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS
setopt HIST_FIND_NO_DUPS

export PATH="$HOME/.local/bin:$PATH"
export PATH="/opt/homebrew/opt/rustup/bin:$PATH"

# Starship prompt
eval "$(starship init zsh)"

# Separate completed commands without adding a blank line before the first prompt.
autoload -Uz add-zsh-hook
typeset -gi STARSHIP_COMMAND_RAN=0
_starship_blank_line_preexec() {
  typeset -g STARSHIP_COMMAND_RAN=1
}
_starship_blank_line_precmd() {
  if (( STARSHIP_COMMAND_RAN )); then
    print
    typeset -g STARSHIP_COMMAND_RAN=0
  fi
}
add-zsh-hook preexec _starship_blank_line_preexec
add-zsh-hook precmd _starship_blank_line_precmd

# Load 1Password shell plugins, including secure GitHub CLI authentication.
source /Users/max.elkins/.config/op/plugins.sh
