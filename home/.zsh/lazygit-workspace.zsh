# lazygit workspace picker
#
# `lg`          context-aware: inside a repo -> lazygit; at a workspace dir -> picker
# `lg w`        force the picker (also bound to Alt-g)
# `lg init [d]` scan d (default $PWD) for git repos, write .lgspace
# `lg add <p>`  append a repo to the nearest .lgspace
# `lg <args>`   anything else is passed straight to lazygit
#
# A .lgspace file lists one repo path per line, relative to the file's dir
# (absolute paths are allowed for out-of-tree repos). '#' starts a comment.

: ${LG_SPACE_FILE:=.lgspace}
: ${LG_SCAN_DEPTH:=6}
typeset -ga LG_ROOTS LG_SCAN_EXCLUDE
(( ${#LG_ROOTS} ))        || LG_ROOTS=(~/Documents/CMS ~/Documents/SideQuest)
(( ${#LG_SCAN_EXCLUDE} )) || LG_SCAN_EXCLUDE=(node_modules target vendor dist build .venv .next)

# --- helpers ---------------------------------------------------------------

# Walk up from $1 (default $PWD), print the first dir holding $LG_SPACE_FILE.
_lg_find_space() {
  local dir=${${1:-$PWD}:A}
  while [[ -n $dir && $dir != / ]]; do
    [[ -f $dir/$LG_SPACE_FILE ]] && { print -r -- $dir; return 0 }
    [[ $dir == $HOME ]] && break
    dir=${dir:h}
  done
  return 1
}

# Print the absolute repo paths listed in $1/$LG_SPACE_FILE.
_lg_members() {
  local dir=$1 line p
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%%\#*}
    line=${${line#"${line%%[![:space:]]*}"}%"${line##*[![:space:]]}"}
    [[ -z $line ]] && continue
    [[ $line == /* ]] && p=$line || p=$dir/$line
    print -r -- ${p:A}
  done < $dir/$LG_SPACE_FILE
}

# Print every git repo under $1. Catches worktrees too (their .git is a file).
_lg_scan() {
  local dir=${${1:-$PWD}:A} g e
  local -a exargs
  for e in $LG_SCAN_EXCLUDE; do exargs+=(-E $e); done
  fd -Hu --max-depth $LG_SCAN_DEPTH $exargs '^\.git$' $dir 2>/dev/null \
    | while IFS= read -r g; do print -r -- ${${g%/}:h:A}; done \
    | sort -u
}

# Path of lazygit's normal, shared state file.
_lg_global_state() {
  print -r -- "${XDG_STATE_HOME:-$HOME/.local/state}/lazygit/state.yml"
}

# Private XDG_STATE_HOME for a workspace, so its recent-repo popup stays its own.
_lg_state_dir() {
  local spacedir=${1:A} h
  h=$(print -rn -- $spacedir | md5sum | cut -c1-8)
  print -r -- "${XDG_STATE_HOME:-$HOME/.local/state}/lg/${spacedir:t}-${h}"
}

# Rewrite the recentrepos block of $1, keeping every other key intact.
_lg_write_recent() {
  local f=$1; shift
  local tmp=$f.lg.$$ r
  {
    [[ -f $f ]] && awk '
      /^recentrepos:/            { skip=1; next }
      skip && /^[[:space:]]*-/   { next }
      { skip=0; print }
    ' $f
    print -r -- "recentrepos:"
    for r in "$@"; do print -r -- "    - $r"; done
  } > $tmp && mv -f $tmp $f
}

# Seed (once, from the global state) and refresh a workspace's state dir.
# Prints the dir, for use as XDG_STATE_HOME.
_lg_state_prepare() {
  local spacedir=$1; shift
  local -a members=("$@") known ordered
  local sd f r m
  sd=$(_lg_state_dir $spacedir)
  f=$sd/lazygit/state.yml
  mkdir -p $sd/lazygit 2>/dev/null || return 1
  [[ -f $f ]] || cp $(_lg_global_state) $f 2>/dev/null
  known=(${(f)"$(_lg_recent $f)"})
  for r in $known; do
    (( ${members[(I)$r]} )) && (( ! ${ordered[(I)$r]} )) && ordered+=$r
  done
  for m in $members; do (( ${ordered[(I)$m]} )) || ordered+=$m; done
  _lg_write_recent $f $ordered || return 1
  print -r -- $sd
}

# Print lazygit's own recent-repo list, most recent first.
_lg_recent() {
  local f=${1:-$(_lg_global_state)}
  [[ -f $f ]] || return 0
  sed -n '/^recentrepos:/,/^[^[:space:]]/p' $f \
    | sed -n "s/^[[:space:]]*-[[:space:]]*//p" \
    | sed -e 's/^["'\'']//' -e 's/["'\'']$//'
}

# Reorder repos: ones lazygit saw recently float to the top, rest keep file order.
_lg_order() {
  local statefile=$1; shift
  local -a members=("$@") recent out
  recent=(${(f)"$(_lg_recent $statefile)"})
  local r m
  for r in $recent; do
    (( ${members[(I)$r]} )) && (( ! ${out[(I)$r]} )) && out+=$r
  done
  for m in $members; do (( ${out[(I)$m]} )) || out+=$m; done
  print -rl -- $out
}

# fzf over repos, displayed relative to $1. Prints the chosen absolute path.
_lg_pick() {
  local base=$1; shift
  local sel r rel
  sel=$(
    for r in "$@"; do
      rel=${r#$base/}
      [[ $rel == $r ]] && rel="${r:t} (root)"
      print -r -- "${rel}"$'\t'"${r}"
    done | fzf --delimiter=$'\t' --with-nth=1 \
               --prompt='repo> ' --height=80% --reverse --no-multi \
               --preview='git -C {2} -c color.status=always status -sb 2>/dev/null; echo; git -C {2} log --oneline --color=always -5 2>/dev/null' \
               --preview-window='right:55%'
  ) || return 1
  [[ -n $sel ]] || return 1
  print -r -- ${sel#*$'\t'}
}

_lg_launch() {
  local base=$1 sd=$2; shift 2
  (( $# )) || { print -u2 "lg: no repos found"; return 1 }
  local statefile=${sd:+$sd/lazygit/state.yml}
  local -a ordered
  ordered=(${(f)"$(_lg_order "$statefile" "$@")"})
  local sel
  sel=$(_lg_pick $base $ordered) || return 1
  if [[ -n $sd ]]; then
    XDG_STATE_HOME=$sd command lazygit -p $sel
  else
    command lazygit -p $sel
  fi
}

# --- subcommands -----------------------------------------------------------

_lg_init() {
  local force=0
  [[ $1 == -f ]] && { force=1; shift }
  local dir=${${1:-$PWD}:A}
  [[ -d $dir ]] || { print -u2 "lg: not a directory: $dir"; return 1 }
  local f=$dir/$LG_SPACE_FILE
  if [[ -e $f && $force -eq 0 ]]; then
    print -u2 "lg: $f exists (use 'lg init -f' to overwrite)"
    return 1
  fi
  local -a found
  found=(${(f)"$(_lg_scan $dir)"})
  (( ${#found} )) || { print -u2 "lg: no git repos under $dir"; return 1 }
  {
    print -r -- "# lazygit workspace, generated $(date -I) by 'lg init'"
    print -r -- "# one repo path per line, relative to this file. '#' starts a comment."
    local r rel
    for r in $found; do
      rel=${r#$dir/}
      [[ $rel == $r ]] && rel=.
      print -r -- $rel
    done
  } > $f
  print -r -- "lg: wrote $f (${#found} repos)"
}

_lg_add() {
  (( $# )) || { print -u2 "lg: usage: lg add <path>..."; return 1 }
  local spacedir
  spacedir=$(_lg_find_space) || {
    print -u2 "lg: no $LG_SPACE_FILE at or above $PWD"; return 1
  }
  local p rel
  for p in "$@"; do
    p=${p:A}
    [[ -d $p ]] || { print -u2 "lg: not a directory: $p"; continue }
    rel=${p#$spacedir/}
    print -r -- $rel >> $spacedir/$LG_SPACE_FILE
    print -r -- "lg: added $rel"
  done
}

# --- entry point -----------------------------------------------------------

_lg_help() {
  local b=$'\e[1m' d=$'\e[2m' r=$'\e[0m'
  [[ -t 1 ]] || { b=""; d=""; r="" }
  print -r -- "${b}lg${r} - lazygit, workspace aware

${b}USAGE${r}
  lg                  context-aware (see RESOLUTION)
  lg w                force the repo picker
  lg init [-f] [dir]  scan dir (default \$PWD) for repos, write ${LG_SPACE_FILE}
  lg add <path>...    append repos to the nearest ${LG_SPACE_FILE}
  lg state            show which lazygit state file applies here
  lg -h               this help
  lg <args>           anything else goes straight to lazygit

${b}RESOLUTION${r} (bare 'lg')
  1. nearest ${LG_SPACE_FILE} found, cwd inside one of its repos   -> lazygit
  2. nearest ${LG_SPACE_FILE} found, cwd is the workspace dir      -> picker
  3. nearest ${LG_SPACE_FILE} found, cwd elsewhere under it        -> picker
  4. no ${LG_SPACE_FILE}, cwd inside a repo                        -> lazygit
  5. no .lgspace, cwd not in a repo                        -> picker over LG_ROOTS

${b}${LG_SPACE_FILE} FORMAT${r}
  One repo path per line, relative to the file's dir. Absolute paths are
  allowed for out-of-tree repos. '#' starts a comment. Order is display
  order; repos in lazygit's own recent list float to the top.

${b}STATE${r}
  A workspace gets its own lazygit state dir, so the recent-repos popup
  (Enter on the status panel) lists only that project. It is seeded once
  from the global state, then kept in sync with ${LG_SPACE_FILE}. Outside a
  workspace the normal global state is used.

${b}PICKER${r}
  fzf, previewing 'git status -sb' plus the last 5 commits.
  Selection runs: lazygit -p <repo>

${b}ENVIRONMENT${r}
  ${d}LG_ROOTS${r}         ${LG_ROOTS}
  ${d}LG_SPACE_FILE${r}    ${LG_SPACE_FILE}
  ${d}LG_SCAN_DEPTH${r}    ${LG_SCAN_DEPTH}
  ${d}LG_SCAN_EXCLUDE${r}  ${LG_SCAN_EXCLUDE}
  ${d}LG_BINDKEY${r}       ${(V)LG_BINDKEY}   ${d}(zle widget, set before sourcing)${r}

${b}NOTE${r}
  For lazygit's own flags: lazygit -h"
}

# Report which lazygit state file the current directory would use.
_lg_state_show() {
  local spacedir
  if spacedir=$(_lg_find_space); then
    print -r -- "workspace: $spacedir"
    print -r -- "state:     $(_lg_state_dir $spacedir)/lazygit/state.yml"
  else
    print -r -- "workspace: (none)"
    print -r -- "state:     $(_lg_global_state)"
  fi
}

_lg_run() {
  local mode=$1 spacedir toplevel
  local -a members

  if spacedir=$(_lg_find_space); then
    members=(${(f)"$(_lg_members $spacedir)"})
    local sd
    sd=$(_lg_state_prepare $spacedir $members) || sd=""
    if [[ $mode == auto && ${PWD:A} != $spacedir ]]; then
      toplevel=$(command git rev-parse --show-toplevel 2>/dev/null)
      if [[ -n $toplevel ]] && (( ${members[(I)${toplevel:A}]} )); then
        if [[ -n $sd ]]; then
          XDG_STATE_HOME=$sd command lazygit
        else
          command lazygit
        fi
        return
      fi
    fi
    _lg_launch $spacedir "$sd" $members
    return
  fi

  if [[ $mode == auto ]] && command git rev-parse --git-dir &>/dev/null; then
    command lazygit
    return
  fi

  local -a all
  local root
  for root in $LG_ROOTS; do
    [[ -d $root ]] && all+=(${(f)"$(_lg_scan $root)"})
  done
  _lg_launch $HOME "" $all
}

# ~/.zshrc defines `alias lg='lazygit'`; the function below supersedes it
# (bare args are passed straight through, so nothing is lost).
unalias lg 2>/dev/null

lg() {
  emulate -L zsh
  case ${1:-} in
    -h|--help|help) _lg_help; return 0 ;;
    state) shift; _lg_state_show; return $? ;;
    w)    shift; _lg_run force; return $? ;;
    init) shift; _lg_init "$@"; return $? ;;
    add)  shift; _lg_add  "$@"; return $? ;;
  esac
  (( $# )) && { command lazygit "$@"; return $? }
  _lg_run auto
}

# Picker from any prompt. Alt-o by default; Alt-g is taken by get-line.
# Override with: LG_BINDKEY='\er'  (set before this file is sourced)
: ${LG_BINDKEY:='\eo'}
if [[ -o interactive ]]; then
  _lg_widget() { BUFFER="lg w"; zle accept-line }
  zle -N _lg_widget
  bindkey $LG_BINDKEY _lg_widget
fi
