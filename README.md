# hyprspace

Make macOS look and behave like [Hyprland](https://hypr.land), using
[AeroSpace](https://github.com/nikitabobko/AeroSpace) as the tiling engine.

One script. No dotfile framework, no submodules, no symlink manager —
`hyprspace.sh` installs the packages and writes every config file itself.

```sh
git clone git@github.com:paulbeavers/hyprspace.git
cd hyprspace
./hyprspace.sh          # install
./uninstall.sh          # undo it all
```

Theme is **Catppuccin Mocha**.

---

## What it sets up

| Hyprland / Wayland | macOS equivalent installed here |
| --- | --- |
| Hyprland (tiling WM) | **AeroSpace** — gaps, workspaces, i3-style binds |
| Border gradients | **JankyBorders** — blue→mauve gradient on the focused window |
| Nerd Font glyphs | **JetBrainsMono Nerd Font** |

## Why there is no status bar

The obvious move is a Waybar clone — SketchyBar — pinned to the top. It isn't
worth it, and this config deliberately leaves it out.

The macOS menu bar owns the top strip. It draws above every window level an
app can reach, so it cannot be covered, and hiding it is unreliable on current
macOS: the documented preferences (`_HIHideMenuBar`,
`AppleMenuBarVisibleInFullscreen`, Control Center's `AutoHideMenuBarOption`)
only take effect at login, and `SLSSetMenuBarAutohideEnabled` in the private
SkyLight framework returns success while `SLSIsMenuBarVisibleOnSpace` keeps
reporting the bar visible.

That leaves three options, none of them good: stack a second bar underneath
the menu bar (redundant, and it eats ~70px of vertical space), move the bar to
the bottom (works, but duplicates a clock, battery and Wi-Fi you already have),
or keep fighting the OS.

On a notched MacBook it gets worse — the centre of a top bar sits behind the
camera housing, so the middle third is unusable.

So: the menu bar keeps doing its job, and this config spends its effort on the
part that actually makes macOS feel like Hyprland — keyboard-driven tiling with
gaps, and a gradient on the focused window. If you want a bar anyway, SketchyBar
installs cleanly alongside this; it just isn't the default.

## Keybinds

AeroSpace uses **ALT** as the modifier — macOS reserves far too much of CMD for
SUPER to work. Everything else maps 1:1 onto Hyprland's defaults.

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
| `alt + /` | **show the keybind cheatsheet** |

## Flags

| Flag | Effect |
| --- | --- |
| `--dry-run` | print every action, change nothing |
| `--configs-only` | skip Homebrew and packages, just rewrite configs |
| `--no-backup` | skip backing up existing configs |
| `-h`, `--help` | usage |

## After the first run

macOS will prompt for **Accessibility** permission for AeroSpace
(System Settings ▸ Privacy & Security ▸ Accessibility). **Nothing tiles until
you grant it and restart AeroSpace.** This is a macOS requirement, not
something the script can do for you.

## A note on gaps

AeroSpace tiles inside macOS's `visibleFrame`, which **already** excludes the
menu bar and the Dock. So `gaps.outer.top` is a true gap on top of that — it
must not include the menu bar height. Adding it leaves a dead strip the height
of the menu bar between the top of the screen and the first window.

## Retheming

The palette lives in one block at the top of `hyprspace.sh`. Change the hex
values, then:

```sh
./hyprspace.sh --configs-only
```

## Uninstalling

`uninstall.sh` reverses everything the installer did: it stops JankyBorders and
quits AeroSpace, uninstalls the packages, deletes the config files, and clears
the macOS menu-bar preferences (by *deleting* the keys, so macOS falls back to
its own defaults rather than a guessed value).

```sh
./uninstall.sh --dry-run    # show the plan, change nothing
./uninstall.sh              # remove packages + configs (asks first)
./uninstall.sh --restore    # also put your ORIGINAL config back
```

| Flag | Effect |
| --- | --- |
| `--dry-run` | print every action, change nothing |
| `-y`, `--yes` | skip the confirmation prompt |
| `--restore` | restore the original pre-hyprspace config from the oldest backup |
| `--keep-packages` | remove configs only, leave Homebrew packages |
| `--keep-configs` | remove packages only, leave config files |
| `--keep-font` | keep JetBrainsMono Nerd Font |
| `--untap` | also remove the Homebrew taps |
| `--purge-backups` | delete `~/.hyprspace-backup` when finished |

`--restore` uses the **oldest** backup on purpose — that's the one taken on the
very first install, i.e. your genuine pre-hyprspace config. Later backups are
just snapshots of hyprspace's own output from repeated runs.

`--untap` refuses to remove a tap while any package from it is still installed,
since that would leave Homebrew unable to resolve the formula.

It also cleans up after older revisions of this repo, which installed SketchyBar
and hid the menu bar — so it leaves no residue even on a machine set up before
those were dropped.

Deliberately left alone: Homebrew itself, your terminal emulator (hyprspace
never installed it), and AeroSpace's Accessibility grant, which only you can
revoke in System Settings.

## Safety

Re-running is safe. Existing configs are copied to
`~/.hyprspace-backup/<timestamp>/` before anything is overwritten, package
installs are skipped when already present, and `--dry-run` shows the whole plan
first.

## Files written

```
~/.aerospace.toml
~/.config/borders/bordersrc
~/.config/hyprspace/keybinds.html
```

`alt + /` opens that last one — a themed cheatsheet of every binding, generated
from the same palette as the borders. It's plain HTML opened in your browser, so
it needs no terminal emulator and no extra dependency.

## Credits

[AeroSpace](https://github.com/nikitabobko/AeroSpace) ·
[JankyBorders](https://github.com/FelixKratz/JankyBorders) ·
[Catppuccin](https://github.com/catppuccin/catppuccin)

## License

MIT
