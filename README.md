# dotfiles

Personal config for an [Omarchy](https://omarchy.org) (Arch + Hyprland) setup.
Only files that diverge from the Omarchy defaults in
`~/.local/share/omarchy/config/` are tracked here.

## Layout

| Path in repo | Installs to |
|---|---|
| `home/.*` | `~/` |
| `icons/default/` | `~/.icons/default/` |
| everything else | `~/.config/<same path>` |

## Install

```sh
git clone https://github.com/Chaingenhash/dotfiles ~/dotfiles
cd ~/dotfiles
for f in home/.*; do [ -f "$f" ] && cp "$f" ~/; done
cp -r icons/default ~/.icons/
rsync -a --exclude README.md --exclude .git --exclude .gitignore \
      --exclude home --exclude icons ./ ~/.config/
```

## What's customized

- **hypr** — PT keyboard layout, natural scroll, dual-monitor (eDP-1 pinned to
  60 Hz on purpose), zero gaps/borders, VRR on, opaque focused windows,
  extra bindings (fullscreen keeps waybar, Super+L locks, Acer F-row quirks).
- **waybar** — mpris module, kanji workspace icons, cpu/memory/GPU readouts,
  `scripts/gpu.sh`.
- **fonts** — Iosevka Nerd Font instead of JetBrainsMono, across ghostty,
  kitty, hyprlock, swayosd, fontconfig.
- **terminals** — ghostty default (`xdg-terminals.list`), OSC52 toast off;
  alacritty carries an explicit Tokyo Night palette.
- **shell** — `home/.zshrc` mirrors Omarchy's bash setup in zsh (fzf-tab,
  starship, mise, zoxide, a zsh-safe `tsl`).
- **misc** — btop layout, lazygit nerd fonts v3, mise toolchain pins,
  wiremix device naming, Bibata-Modern-Ice cursor, chromium theme extension.

## Not tracked

- `~/.config/git/config` — machine-local identity and credential helpers.
- `~/.XCompose` — only customization is a compose shortcut that expands to a
  personal email address.

Both are deliberately kept out of a public repo.
