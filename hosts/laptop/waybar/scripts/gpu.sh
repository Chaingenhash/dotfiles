#!/bin/bash
# Intel iGPU utilization for waybar.
#
# Long-lived: waybar runs this once (no "interval" on the module) and reads
# stdout line by line, so intel_gpu_top is started a single time instead of
# being respawned every few seconds.
#
# Reports the busiest engine rather than Render/3D alone -- video decode and
# compute workloads live on separate engines, and a Render-only reading shows
# 0% while a video is playing.
#
# The busiest engine's raw busy% is NOT shown, because it measures engine
# occupancy, not work: a terminal repainting its cursor keeps Render/3D "busy"
# ~97% of the time while the GT sits at 100MHz of its 1950MHz ceiling drawing
# 0.3W. That reads as a pegged GPU when 95% of the capacity is idle. So the
# figure in the bar is occupancy scaled by the clock the GT actually settled at
# -- 97% busy at 100/1950MHz becomes 5%. A real load ramps the clock, so it
# still reaches 100%. The tooltip keeps the unscaled numbers for debugging.
#
# Requires: intel-gpu-tools with CAP_PERFMON granted to the binary:
#   sudo setcap cap_perfmon+ep /usr/bin/intel_gpu_top
# (a pacman upgrade of intel-gpu-tools wipes this; see the pacman hook).

set -uo pipefail

PERIOD_MS=2000

# Hardware maximum GT clock (RP0). Not gt_max_freq_mhz -- that one is the
# writable current cap, so a power-management tweak lowering it would silently
# inflate every reading. 0 disables scaling and falls back to raw occupancy.
MAX_MHZ=0
for f in /sys/class/drm/card*/gt_RP0_freq_mhz; do
  [[ -r $f ]] || continue
  read -r MAX_MHZ <"$f" || MAX_MHZ=0
  [[ $MAX_MHZ =~ ^[0-9]+$ ]] || MAX_MHZ=0
  ((MAX_MHZ > 0)) && break
done

emit() { # $1 = scaled pct, $2 = raw busy pct, $3 = actual MHz, $4 = centiwatts
  if [[ -z ${1:-} ]]; then
    printf '{"text":"","tooltip":"GPU stats unavailable","class":"unavailable"}\n'
    return
  fi
  local pct=$1 raw=$2 mhz=$3 cw=$4
  local class=""
  ((pct >= 90)) && class="critical"
  ((pct >= 70 && pct < 90)) && class="warning"
  # The glyph lives here, not in the module's "format": waybar still renders
  # format literals around an empty {}, so a bare "GPU %" would linger whenever
  # stats are unavailable. With format "{}" an empty text hides the module.
  printf '{"text":"󰢮 %s%%","tooltip":"GPU %s%% · busiest engine %s%% busy at %s/%sMHz · %s.%02dW","class":"%s"}\n' \
    "$pct" "$pct" "$raw" "$mhz" "$MAX_MHZ" "$((cw / 100))" "$((cw % 100))" "$class"
}

if ! command -v intel_gpu_top &>/dev/null; then
  emit ""
  exec sleep infinity
fi

# Start intel_gpu_top via process substitution so we hold its PID and can reap
# it on exit. Without this it outlives us: waybar SIGTERMs the script on
# restart, the child is never signalled, and every `omarchy restart waybar`
# strands another intel_gpu_top sampling the GPU forever.
exec 3< <(exec intel_gpu_top -J -s "$PERIOD_MS" 2>/dev/null)
igt_pid=$!

cleanup() {
  kill "$igt_pid" 2>/dev/null
  kill "${pipe_pid:-}" 2>/dev/null
}
trap cleanup EXIT
# TERM must exit outright, not merely clean up: waybar SIGTERMs this script on
# restart, and without the explicit exit control falls through to the
# `sleep infinity` tail below, stranding a sleep process per restart.
trap 'cleanup; exit 0' TERM INT HUP

# intel_gpu_top -J emits a stream of JSON objects. Rather than assume a stable
# top-level shape across versions, pull every engine's "busy" value and keep the
# max, then scale it by frequency.actual/RP0. jq --unbuffered keeps latency at
# one sample period. Power is passed as centiwatts so bash never sees a float.
#
# This runs in the BACKGROUND and is waited on below. Backgrounding is load
# bearing: bash defers trap handlers while blocked on a foreground command, so
# with the pipeline in the foreground the TERM trap never fires and both
# intel_gpu_top and this script survive a waybar restart. `wait` is
# interruptible, so signals are handled promptly.
{
  jq --unbuffered -rn --stream --argjson max "$MAX_MHZ" '
      fromstream(1|truncate_stream(inputs))
      | [ .engines // {} | .[]? | .busy? // 0 ] as $engines
      | if ($engines | length) == 0 then empty
        else
          ($engines | max) as $busy
          | (.frequency.actual // 0) as $mhz
          | (.power.GPU // 0) as $watts
          | (if $max > 0 then ($busy * $mhz / $max) else $busy end) as $scaled
          | "\($scaled|floor) \($busy|floor) \($mhz|floor) \(($watts * 100)|floor)"
        end
    ' <&3 2>/dev/null \
  | while read -r pct raw mhz cw; do
      [[ $pct =~ ^[0-9]+$ && $raw =~ ^[0-9]+$ ]] || continue
      # intel_gpu_top's first period is a ~14ms fragment, not PERIOD_MS, so its
      # busy figure is a meaningless spike. Drop it.
      if [[ -z ${primed:-} ]]; then primed=1; continue; fi
      ((pct > 100)) && pct=100
      ((raw > 100)) && raw=100
      emit "$pct" "$raw" "$mhz" "$cw"
    done
} &
pipe_pid=$!

wait "$pipe_pid"

# intel_gpu_top died (permissions, driver, unplug) -- degrade visibly instead of
# leaving a stale number frozen in the bar. Reap explicitly: `exec` below
# replaces this shell and would discard the EXIT trap.
cleanup
emit ""
exec sleep infinity
