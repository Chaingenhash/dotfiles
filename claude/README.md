# Claude Code

Installs to `~/.claude/`. Only hand-written config lives here — everything
else in `~/.claude/` is runtime state (sessions, transcripts, caches,
`.credentials.json`) and is not tracked.

| File | What |
|---|---|
| `settings.json` | plugins + marketplaces, fullscreen TUI, `darky` theme, statusline, `pw-play` sound hooks on Stop/Notification, co-authored-by off |
| `statusline.sh` | two-line statusline: context %, rate limits, prompt cache, cost, model/effort, cwd/branch/PR |
| `settings.local.json` | machine-local permission allowlist |
| `themes/darky.json` | dark theme with an orange accent |

## Plugins

Declared in `settings.json` and reinstalled by Claude Code on first run:
`caveman`, `superpowers`, `ui-ux-pro-max`, `frontend-design`.

## Skills

`~/.claude/skills/` holds symlinks, not files — recreate them by hand:

```sh
ln -s ~/Documents/SideQuest/claude-skills/skills/commit-review ~/.claude/skills/commit-review
ln -s ~/Documents/SideQuest/claude-skills/skills/commit-fix    ~/.claude/skills/commit-fix
ln -s ~/.local/share/omarchy/default/omarchy-skill             ~/.claude/skills/omarchy
```

`commit-review` / `commit-fix` live in the separate `claude-skills` repo.
`omarchy` ships with Omarchy.

## Not tracked

`~/.claude.json` (account id, machine id, per-project history) and
`~/.claude/projects/*/memory/` (project memories, several from work repos).

## Statusline

`statusline.sh` reads the status JSON on stdin and prints two lines:

```
[CAVEMAN] · Opus 5 high think · @Explore · dev/portal-sibs · ⎇ main · #128/APPROVED
ctx ███████░░░ 73% 146k/200k · cache warm 93% · 5h 31%(2h) 7d 76%(63h) · $1.23 1h15m +420/-77
```

- **ctx** — `context_window.used_percentage` (already 0–100), bar recoloured at
  50 / 75 / 90. The early warning before auto-compact.
- **cache** — `prompt_cache.warm` + `hit_ratio`. A cold cache is why a session
  suddenly costs more and answers slower.
- **5h / 7d / op / lim** — `rate_limits.*.utilization`, a 0–1 fraction
  (`YKt(e) = round(e*1000)/10` in the binary), with time to reset; the reset is
  hidden when it is further out than a week.
- **model line** — `display_name`, `effort.level`, `thinking.enabled`,
  `fast_mode` (orange: it changes behaviour), `agent.name` when a subagent runs.
- **cost** — `total_cost_usd`, session duration, lines added/removed.

Branch comes from `git branch --show-current`, not from the payload's
`workspace.git_worktree` (undocumented shape). The caveman badge is inlined
from the plugin's own `caveman-statusline.sh`, with the same hardening
(rejects a symlinked flag, caps the read at 64 bytes, whitelists the modes) —
so a plugin update no longer breaks the statusline path.

Schema verified against Claude Code 2.1.330. Omitted on purpose:
`session_id`, `output_style`, `version`, and `exceeds_200k_tokens` (redundant —
the window size already shows `/1M` vs `/200k`).

## Note

`settings.json` hardcodes `/home/guilherme/.claude/statusline.sh` as an
absolute path. Change it if the repo is ever used under a different username.
