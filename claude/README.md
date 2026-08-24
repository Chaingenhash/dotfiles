# Claude Code

Installs to `~/.claude/`. Only hand-written config lives here — everything
else in `~/.claude/` is runtime state (sessions, transcripts, caches,
`.credentials.json`) and is not tracked.

| File | What |
|---|---|
| `settings.json` | plugins + marketplaces, fullscreen TUI, `darky` theme, statusline, `pw-play` sound hooks on Stop/Notification, co-authored-by off |
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

## Note

`settings.json` hardcodes an absolute statusline path containing the caveman
plugin's commit sha. It breaks when that plugin updates — repoint it at the
current `~/.claude/plugins/cache/caveman/caveman/<sha>/hooks/caveman-statusline.sh`.
