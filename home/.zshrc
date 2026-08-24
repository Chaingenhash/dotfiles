# ~/.zshrc — zsh setup mirroring omarchy's bash config
# Canonical omarchy config still lives in bash (~/.bashrc -> omarchy/default/bash/*).
# This file re-uses the POSIX-compatible parts and adds zsh equivalents.

export OMARCHY_PATH=$HOME/.local/share/omarchy

# --- Preexisting toolchain exports ---
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
export PATH=$JAVA_HOME/bin:$PATH
export ANDROID_HOME=$HOME/Android/Sdk
export PATH=$ANDROID_HOME/platform-tools:$PATH

# --- pnpm ---
export PNPM_HOME="$HOME/.local/share/pnpm"
typeset -U path                       # zsh: auto-dedupe PATH entries
path=("$PNPM_HOME/bin" $path)

# --- History (replaces omarchy bash/shell) ---
HISTFILE=~/.zsh_history
HISTSIZE=32768
SAVEHIST=$HISTSIZE
setopt APPEND_HISTORY INC_APPEND_HISTORY SHARE_HISTORY
setopt HIST_IGNORE_ALL_DUPS HIST_IGNORE_SPACE

# --- Completion system (must init before fzf-tab) ---
autoload -Uz compinit && compinit
zstyle ':completion:*' menu no                              # let fzf-tab own the menu
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'   # case-insensitive

# --- Env vars (pure exports, sourced straight from omarchy) ---
source "$OMARCHY_PATH/default/bash/envs"

# --- Aliases + functions (zsh-compatible, sourced from omarchy) ---
source "$OMARCHY_PATH/default/bash/aliases"
source "$OMARCHY_PATH/default/bash/functions"

# --- Personal aliases ---
alias lg='lazygit'
alias ldk='lazydocker'

# zsh fix: omarchy `tsl` uses 0-based array index (bash). zsh arrays are 1-based.
tsl() {
  [[ -z $1 || -z $2 ]] && { echo "Usage: tsl <pane_count> <command>"; return 1; }
  [[ -z $TMUX ]] && { echo "You must start tmux to use tsl."; return 1; }
  local count="$1" cmd="$2" current_dir="${PWD}"
  local -a panes
  tmux rename-window -t "$TMUX_PANE" "$(basename "$current_dir")"
  panes+=("$TMUX_PANE")
  while (( ${#panes[@]} < count )); do
    local new_pane split_target="${panes[-1]}"
    new_pane=$(tmux split-window -h -t "$split_target" -c "$current_dir" -P -F '#{pane_id}')
    panes+=("$new_pane")
    tmux select-layout -t "${panes[1]}" tiled
  done
  for pane in "${panes[@]}"; do tmux send-keys -t "$pane" "$cmd" C-m; done
  tmux select-pane -t "${panes[1]}"
}

# --- Tool inits (zsh variants of omarchy bash/init) ---
command -v mise     &>/dev/null && eval "$(mise activate zsh)"
[[ $- == *i* && ${TERM:-} != dumb ]] && command -v starship &>/dev/null && eval "$(starship init zsh)"
command -v zoxide   &>/dev/null && eval "$(zoxide init zsh)"

if command -v try &>/dev/null; then
  try() { unset -f try; eval "$(SHELL=/bin/bash command try init ~/Work/tries)"; try "$@"; }
fi

# --- fzf: completion + keybindings, then fzf-tab (interactive Tab menu) ---
if command -v fzf &>/dev/null; then
  [[ -f /usr/share/fzf/completion.zsh ]]   && source /usr/share/fzf/completion.zsh
  [[ -f /usr/share/fzf/key-bindings.zsh ]] && source /usr/share/fzf/key-bindings.zsh
fi
[[ -f ~/.zsh/fzf-tab/fzf-tab.plugin.zsh ]] && source ~/.zsh/fzf-tab/fzf-tab.plugin.zsh
