# hyprspace

Make macOS look and behave like [Hyprland](https://hypr.land), using
[AeroSpace](https://github.com/nikitabobko/AeroSpace) as the tiling engine.

One script. No dotfile framework, no submodules, no symlink manager — `hyprspace.sh`
installs the packages and writes every config file itself.

```sh
git clone https://github.com/<you>/hyprspace.git
cd hyprspace
./hyprspace.sh
```

Theme is **Catppuccin Mocha**.

---

## What it sets up

| Hyprland / Wayland | macOS equivalent installed here |
| --- | --- |
| Hyprland (tiling WM) | **AeroSpace** — gaps, workspaces, i3-style binds |
| Border gradients | **JankyBorders** — blue→mauve gradient on the focused window |
| Waybar | **SketchyBar** — floating rounded bar, workspace pills, status modules |
| Nerd Font glyphs | **JetBrainsMono Nerd Font** + **sketchybar-app-font** |

The bar carries workspace pills (active / occupied / empty, like Hyprland's), the
focused app with its real icon, a binding-mode badge, a centred clock, and
CPU / memory / Wi-Fi / volume / battery on the right.

## Keybinds

AeroSpace uses **ALT** as the modifier — macOS reserves far too much of CMD for
this to work on SUPER. Everything else maps 1:1 onto Hyprland's defaults.

| Key | Action |
| --- | --- |
| `alt + Return` | terminal (auto-detects kitty / Ghostty / Alacritty / WezTerm / iTerm) |
| `alt + E` | Finder |
| `alt + Q` | close window |
| `alt + V` | toggle floating |
| `alt + F` | fullscreen |
| `alt + S` | toggle split direction |
| `alt + h/j/k/l` | focus (arrow keys work too) |
| `alt + shift + h/j/k/l` | move window |
| `alt + ctrl + h/j/k/l` | resize |
| `alt + 1…9,0` | switch workspace |
| `alt + shift + 1…9,0` | send window to workspace and follow |
| `alt + Tab` | last workspace |
| `alt + ctrl + ←/→` | cycle workspaces |
| `alt + shift + Tab` | move workspace to next monitor |
| `alt + R` | resize submap (`Esc` exits) |
| `alt + shift + ;` | service mode (`Esc` reloads config) |

## Flags

| Flag | Effect |
| --- | --- |
| `--dry-run` | print every action, change nothing |
| `--configs-only` | skip Homebrew and packages, just rewrite configs |
| `--no-backup` | skip backing up existing configs |
| `--keep-menubar` | leave the macOS menu bar visible |
| `-h`, `--help` | usage |

## After the first run

macOS will prompt for **Accessibility** permission for AeroSpace
(System Settings ▸ Privacy & Security ▸ Accessibility). **Nothing tiles until you
grant it and restart AeroSpace.** This is a macOS requirement, not something the
script can do for you.

### The macOS menu bar

macOS draws its menu bar above every window, SketchyBar included — no window
level available to a normal app wins, so it cannot be covered. The script hides
it instead, via `SLSSetMenuBarAutohideEnabled` in the private SkyLight framework
(loaded by `dlopen`/`dlsym`, so a missing symbol degrades to a warning rather
than a build failure).

That flag is **WindowServer state, not a preference** — it resets on reboot. So
the script compiles a small helper to `~/.config/hyprspace/hyprspace-menubar` and
AeroSpace re-runs it at startup:

```sh
~/.config/hyprspace/hyprspace-menubar --hide     # hide
~/.config/hyprspace/hyprspace-menubar --show     # show
~/.config/hyprspace/hyprspace-menubar --toggle   # toggle  (bound to alt+shift+M)
```

It also writes the matching preferences (`_HIHideMenuBar`,
`AppleMenuBarVisibleInFullscreen`, and Control Center's `AutoHideMenuBarOption`)
so the state survives a logout. `NSGlobalDomain` is not addressable through
`UserDefaults(suiteName:)`, so those go through `CFPreferences`.

**Reaching the menu bar when it's hidden:** push the pointer into the very top
edge to reveal it, or press **Ctrl+F2** (`Fn+Ctrl+F2` on a laptop keyboard) to
move focus there from the keyboard. `alt+shift+M` brings it back permanently.

### The notch

On a notched MacBook the centre of the bar sits behind the camera housing. The
script measures `NSScreen.safeAreaInsets.top` and adapts:

| Display | Bar |
| --- | --- |
| notched | full-width, flush at `y=0`, square corners, **centre left empty** |
| no notch | floating rounded bar with margins and a border |

All modules live on the left (workspaces, mode, focused app) and right (memory,
CPU, Wi-Fi, volume, battery, clock). Nothing is ever placed in the centre on a
notched machine. `gaps.outer.top` is derived from whichever layout applies.

## Retheming

The palette lives in one block at the top of `hyprspace.sh`. Change the hex values,
then:

```sh
./hyprspace.sh --configs-only
```

Everything — bar, workspace pills, status colors, window border gradient — is
generated from those variables, so a retheme is a single edit.

Bar geometry is in the same block (`BAR_HEIGHT`, `BAR_Y_OFFSET`, `BAR_MARGIN`,
`GAP_INNER`). AeroSpace's top gap is *derived* from them, so windows can never
end up underneath the bar.

## Safety

Re-running is safe. Existing configs are copied to
`~/.hyprspace-backup/<timestamp>/` before anything is overwritten, package installs
are skipped when already present, and `--dry-run` shows the whole plan first.

## Files written

```
~/.aerospace.toml
~/.config/borders/bordersrc
~/.config/sketchybar/sketchybarrc
~/.config/sketchybar/colors.sh
~/.config/sketchybar/plugins/*.sh
```

## Notes

- **Wi-Fi module shows "Wi-Fi", not the SSID.** Reading the SSID on current macOS
  requires a Location Services grant and silently returns empty without it, so the
  module reports link type instead.
- **CPU** is sampled as summed per-process `%cpu` over core count rather than
  `top -l 2`, which would block for a full sample interval on every tick.
- Blur behind the bar is SketchyBar's own `blur_radius`; macOS has no compositor
  hook for per-window blur, so Hyprland-style window blur isn't reproducible.

## Credits

[AeroSpace](https://github.com/nikitabobko/AeroSpace) ·
[SketchyBar](https://github.com/FelixKratz/SketchyBar) ·
[JankyBorders](https://github.com/FelixKratz/JankyBorders) ·
[sketchybar-app-font](https://github.com/kvndrsslr/sketchybar-app-font) ·
[Catppuccin](https://github.com/catppuccin/catppuccin)

## License

MIT
