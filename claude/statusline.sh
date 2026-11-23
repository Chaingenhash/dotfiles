#!/bin/bash
# Claude Code statusline — session + context info.
# Payload schema verified against claude 2.1.330.
# Line 1: caveman badge · model/effort/thinking/fast · agent · dir · branch · PR
# Line 2: context bar · prompt cache · rate limits · cost/duration/lines

input=$(cat)
[ -z "$input" ] && exit 0

# --- caveman badge (inlined from the plugin script, same hardening) ---
CAV=""
FLAG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.caveman-active"
if [ -f "$FLAG" ] && [ ! -L "$FLAG" ]; then
  MODE=$(head -c 64 "$FLAG" 2>/dev/null | tr -d '\n\r' | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
  case "$MODE" in
    off) ;;
    ""|full) CAV="CAVEMAN" ;;
    lite|ultra|wenyan-lite|wenyan|wenyan-full|wenyan-ultra|commit|review|compress)
      CAV="CAVEMAN:$(printf '%s' "$MODE" | tr '[:lower:]' '[:upper:]')" ;;
  esac
fi

cwd=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // ""')
branch=""
[ -n "$cwd" ] && branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)

printf '%s' "$input" | jq -r --arg cav "$CAV" --arg branch "$branch" '
  def R: "\u001b[0m";
  def c($n): "\u001b[38;5;\($n)m" + . + R;
  def dim: "\u001b[2m" + . + R;
  def sep: " " + ("·" | dim) + " ";

  def kfmt:
    if . == null then "?"
    elif . >= 1000000 then "\((. / 100000 | floor) / 10)M"
    elif . >= 1000 then "\(. / 1000 | floor)k"
    else "\(.)" end;

  def dur:
    (. / 1000 | floor) as $s
    | if $s >= 3600 then "\($s / 3600 | floor)h\(($s % 3600) / 60 | floor)m"
      elif $s >= 60 then "\($s / 60 | floor)m"
      else "\($s)s" end;

  def pctcolor($p):
    if $p < 50 then c(114) elif $p < 75 then c(221)
    elif $p < 90 then c(214) else c(203) end;

  def bar($p):
    ($p / 10 | floor) as $f
    | (if $f > 0 then "█" * $f else "" end) + (if $f < 10 then "░" * (10 - $f) else "" end);

  # ---------- line 1 ----------
  ([ (if $cav != "" then ("[" + $cav + "]" | c(172)) else empty end),

     ([ (.model.display_name // .model.id // "?" | c(111)),
        (.effort.level // empty | c(139)),
        (if .thinking.enabled then ("think" | c(139)) else empty end),
        (if .fast_mode then ("fast" | c(208)) else empty end)
      ] | join(" ")),

     (if .agent.name then ("@" + .agent.name | c(176)) else empty end),

     ((.workspace.current_dir // .cwd // "")
      | if . != "" then
          sub("^" + env.HOME; "~") | split("/") | (if length > 2 then .[-2:] else . end) | join("/") | c(109)
        else empty end),

     ((.worktree.branch // $branch) as $b | if $b != "" then ("⎇ " + $b | c(72)) else empty end),
     (if .worktree.name then ("wt:" + .worktree.name | c(72)) else empty end),

     (if .pr.number then
        ("#\(.pr.number)" + (if .pr.review_state then "/" + .pr.review_state else "" end) | c(170))
      else empty end)
   ] | join(sep)),

  # ---------- line 2 ----------
  ([ (.context_window as $w
      | if $w and $w.used_percentage != null then
          ($w.used_percentage) as $p
          | ("ctx " | dim) + (bar($p) | pctcolor($p)) + " "
            + ("\($p)%" | pctcolor($p))
            + (" \($w.total_input_tokens | kfmt)/\($w.context_window_size | kfmt)" | dim)
        else empty end),

     (.prompt_cache as $pc
      | if $pc then
          ("cache " | dim)
          + (if $pc.warm then ("warm" | c(114)) else ("cold" | c(203)) end)
          + (if $pc.hit_ratio != null then (" \($pc.hit_ratio * 100 | floor)%" | dim) else "" end)
        else empty end),

     (.rate_limits as $rl
      | if $rl then
          ( [ {k: "5h",  v: $rl.five_hour},
              {k: "7d",  v: $rl.seven_day},
              {k: "op",  v: $rl.seven_day_opus},
              {k: "lim", v: $rl.spend_limit} ]
            | map(select(.v != null and .v.utilization != null))
            | map( (.v.utilization * 100 | floor) as $p
                   | (.k | dim) + " " + ("\($p)%" | pctcolor($p))
                   + (if .v.resets_at then
                        ((.v.resets_at - now) | if . > 0 and . < 604800 then
                           (if . >= 3600 then "(\(. / 3600 | floor)h)" else "(\(. / 60 | floor)m)" end | dim)
                         else "" end)
                      else "" end) )
            | if length > 0 then join(" ") else empty end )
        else empty end),

     (.cost as $co
      | if $co then
          ([ ("$\($co.total_cost_usd * 100 | round / 100)" | c(179)),
             (if $co.total_duration_ms then ($co.total_duration_ms | dur | dim) else empty end),
             (if ($co.total_lines_added // 0) > 0 or ($co.total_lines_removed // 0) > 0 then
                ("+\($co.total_lines_added // 0)" | c(114)) + ("/" | dim) + ("-\($co.total_lines_removed // 0)" | c(203))
              else empty end)
           ] | join(" "))
        else empty end)
   ] | map(select(. != null and . != ""))
     | if length > 0 then join(sep) else empty end)
'
