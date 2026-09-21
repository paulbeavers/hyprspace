#!/usr/bin/env bash
# ============================================================================
#  hyprspace.sh — make macOS + AeroSpace look and behave like Hyprland
# ============================================================================
#
#  One self-contained, idempotent, re-runnable script. Copy it to any Mac and
#  run it; it installs everything and writes every config file itself.
#
#    ./hyprspace.sh
#
#  What it sets up
#    AeroSpace      tiling WM        <- the i3/Hyprland core
#    JankyBorders   gradient borders <- Hyprland's focused-window glow
#    JetBrainsMono Nerd Font
#
#  Theme: Catppuccin Mocha (edit the PALETTE block below to retheme)
#
#  Flags
#    --dry-run        print what would happen, touch nothing
#    --configs-only   skip Homebrew/package installation, just rewrite configs
#    --no-backup      don't back up existing configs (default: always back up)
#    -h | --help
#
#  Deliberately NOT included: a status bar. The macOS menu bar already owns
#  the top strip -- it draws above every window level an app can reach, so it
#  cannot be covered, and hiding it is unreliable on current macOS. Rather
#  than stack a second bar beneath it or work around the notch, this config
#  leaves the menu bar to do its job (clock, battery, Wi-Fi, app menus) and
#  spends its effort on what actually makes macOS feel like Hyprland:
#  keyboard-driven tiling with gaps, and a gradient on the focused window.
#
# ============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# PALETTE — Catppuccin Mocha. JankyBorders wants 0xAARRGGBB.
# ---------------------------------------------------------------------------
THEME_NAME="Catppuccin Mocha"

HEX_BLUE="89b4fa"      # focused border, gradient start
HEX_MAUVE="cba6f7"     # focused border, gradient end
HEX_SURF1="45475a"     # unfocused border

# Gaps, in points. Hyprland's defaults sit around 5/10; 10 suits a laptop.
GAP_INNER=10
GAP_OUTER=10

# Border thickness on the focused window.
BORDER_WIDTH=5.0

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
DRY_RUN=0
CONFIGS_ONLY=0
DO_BACKUP=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)      DRY_RUN=1 ;;
    --configs-only) CONFIGS_ONLY=1 ;;
    --no-backup)    DO_BACKUP=0 ;;
    -h|--help)      sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown flag: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  C_RST=$'\033[0m'; C_B=$'\033[1m'; C_DIM=$'\033[2m'
  C_BLU=$'\033[38;5;111m'; C_GRN=$'\033[38;5;114m'
  C_YEL=$'\033[38;5;222m'; C_RED=$'\033[38;5;210m'
else
  C_RST=""; C_B=""; C_DIM=""; C_BLU=""; C_GRN=""; C_YEL=""; C_RED=""
fi

step() { printf '\n%s%s==>%s %s%s%s\n' "$C_B" "$C_BLU" "$C_RST" "$C_B" "$*" "$C_RST"; }
info() { printf '    %s\n' "$*"; }
ok()   { printf '    %s✓%s %s\n' "$C_GRN" "$C_RST" "$*"; }
warn() { printf '    %s!%s %s\n' "$C_YEL" "$C_RST" "$*"; }
die()  { printf '\n%serror:%s %s\n\n' "$C_RED" "$C_RST" "$*" >&2; exit 1; }

run() {
  if (( DRY_RUN )); then printf '    %s$ %s%s\n' "$C_DIM" "$*" "$C_RST"
  else "$@"
  fi
}

# write_file <path> — content on stdin. Honours --dry-run.
write_file() {
  local path="$1" dir
  dir="$(dirname "$path")"
  if (( DRY_RUN )); then
    printf '    %swrite %s (%s lines)%s\n' "$C_DIM" "$path" "$(wc -l)" "$C_RST"
    return
  fi
  mkdir -p "$dir"
  cat > "$path"
  ok "wrote ${path/#$HOME/\~}"
}

BORDERS_DIR="$HOME/.config/borders"
AERO_CONF="$HOME/.aerospace.toml"
BACKUP_DIR="$HOME/.hyprspace-backup/$(date +%Y%m%d-%H%M%S)"

printf '\n%s%s  hyprspace%s  %s— AeroSpace, dressed as Hyprland%s\n' \
  "$C_B" "$C_BLU" "$C_RST" "$C_DIM" "$C_RST"
printf '  %stheme: %s   gaps: %spx%s\n' "$C_DIM" "$THEME_NAME" "$GAP_INNER" "$C_RST"
(( DRY_RUN )) && printf '  %s[dry run — nothing will be modified]%s\n' "$C_YEL" "$C_RST"

# ===========================================================================
# 1. Preflight
# ===========================================================================
step "Preflight"

[[ "$(uname -s)" == "Darwin" ]] || die "this script is macOS-only (found $(uname -s))"
ok "macOS $(sw_vers -productVersion) on $(uname -m)"

if ! xcode-select -p >/dev/null 2>&1; then
  warn "Xcode Command Line Tools missing — triggering the installer"
  run xcode-select --install || true
  die "rerun this script once the Command Line Tools finish installing"
fi
ok "Xcode Command Line Tools present"

if ! command -v brew >/dev/null 2>&1; then
  # Homebrew may be installed but not on PATH yet (fresh machine, new shell).
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [[ -x "$candidate" ]] && eval "$("$candidate" shellenv)" && break
  done
fi

if ! command -v brew >/dev/null 2>&1; then
  if (( CONFIGS_ONLY )); then
    warn "Homebrew not found, but --configs-only was passed; continuing"
  else
    step "Installing Homebrew"
    HOMEBREW_INSTALLER="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
    if (( DRY_RUN )); then
      info "would run the Homebrew installer non-interactively"
    else
      NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL "$HOMEBREW_INSTALLER")" \
        || die "Homebrew install failed"
    fi
    for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
      [[ -x "$candidate" ]] && eval "$("$candidate" shellenv)" && break
    done
    command -v brew >/dev/null 2>&1 || die "Homebrew installed but 'brew' is still not on PATH"
  fi
fi
command -v brew >/dev/null 2>&1 && ok "Homebrew $(brew --version | head -1 | awk '{print $2}')"

# ===========================================================================
# 2. Packages
# ===========================================================================
if (( CONFIGS_ONLY )); then
  step "Packages"; info "skipped (--configs-only)"
else
  step "Taps"
  # Homebrew >= 7 refuses to load formulae from untrusted third-party taps.
  trust_tap() {
    if brew trust --help >/dev/null 2>&1; then
      run brew trust --tap "$1" >/dev/null 2>&1 || true
    fi
  }
  for tap in nikitabobko/tap FelixKratz/formulae; do
    if brew tap | grep -qix "$tap"; then
      ok "$tap (already tapped)"
    else
      run brew tap "$tap" && ok "$tap"
    fi
    trust_tap "$tap"
  done

  step "Formulae & casks"
  install_formula() {
    if brew list --formula --versions "$1" >/dev/null 2>&1; then ok "$1 (already installed)"
    else info "installing $1…"; run brew install "$1" && ok "$1"; fi
  }
  install_cask() {
    if brew list --cask --versions "$1" >/dev/null 2>&1; then ok "$1 (already installed)"
    else info "installing $1…"; run brew install --cask "$1" && ok "$1"; fi
  }

  install_cask    nikitabobko/tap/aerospace
  install_formula FelixKratz/formulae/borders
  install_cask    font-jetbrains-mono-nerd-font
fi

# ===========================================================================
# 3. Detect a terminal for the alt+Return binding
# ===========================================================================
step "Terminal"
TERMINAL_CMD=""
for app in kitty Ghostty Alacritty WezTerm iTerm; do
  if [[ -d "/Applications/$app.app" ]]; then
    TERMINAL_CMD="open -na \"$app\""
    ok "alt+Return will launch $app"
    break
  fi
done
if [[ -z "$TERMINAL_CMD" ]]; then
  TERMINAL_CMD="open -na Terminal"
  warn "no modern terminal found — falling back to Terminal.app"
  info "for the real look: brew install --cask kitty  (then rerun)"
fi

# ===========================================================================
# 4. Back up whatever is already there
# ===========================================================================
if (( DO_BACKUP )); then
  step "Backup"
  backed_up=0
  for target in "$AERO_CONF" "$BORDERS_DIR"; do
    if [[ -e "$target" ]]; then
      run mkdir -p "$BACKUP_DIR"
      run cp -R "$target" "$BACKUP_DIR/"
      ok "saved ${target/#$HOME/\~}"
      backed_up=1
    fi
  done
  (( backed_up )) && info "backup: ${BACKUP_DIR/#$HOME/\~}" \
                  || info "nothing to back up (clean machine)"
else
  step "Backup"; info "skipped (--no-backup)"
fi

# ===========================================================================
# 5. AeroSpace
# ===========================================================================
step "AeroSpace config"

write_file "$AERO_CONF" <<AEROSPACE_TOML
# ~/.aerospace.toml — generated by hyprspace.sh
# Hyprland-style tiling. Modifier is ALT (macOS reserves too much of CMD).
# Hyprland's SUPER+<key> becomes ALT+<key> throughout.

config-version = 2

start-at-login = true
auto-reload-config = true

enable-normalization-flatten-containers = true
enable-normalization-opposite-orientation-for-nested-containers = true

accordion-padding = 30
default-root-container-layout = 'tiles'
default-root-container-orientation = 'auto'

automatically-unhide-macos-hidden-apps = true
focus-follows-mouse.enabled = false
on-focused-monitor-changed = ['move-mouse monitor-lazy-center']

key-mapping.preset = 'qwerty'

# Hyprland-style numbered workspaces.
persistent-workspaces = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

# --- Gaps -------------------------------------------------------------------
# AeroSpace tiles inside macOS's visibleFrame, which ALREADY excludes the menu
# bar and the Dock. These are true gaps on top of that — adding the menu bar
# height here would double-count it and leave a dead strip at the top.
gaps.inner.horizontal = ${GAP_INNER}
gaps.inner.vertical   = ${GAP_INNER}
gaps.outer.top        = ${GAP_OUTER}
gaps.outer.bottom     = ${GAP_OUTER}
gaps.outer.left       = ${GAP_OUTER}
gaps.outer.right      = ${GAP_OUTER}

# --- Startup ----------------------------------------------------------------
after-startup-command = [
  'exec-and-forget /bin/bash -lc "command -v borders >/dev/null && borders &"',
]

# --- Window rules (Hyprland's windowrulev2 float,...) ------------------------
[[on-window-detected]]
if.app-id = 'com.apple.systempreferences'
run = 'layout floating'

[[on-window-detected]]
if.app-id = 'com.apple.ActivityMonitor'
run = 'layout floating'

[[on-window-detected]]
if.app-id = 'com.apple.finder'
if.window-title-regex-substring = 'Info'
run = 'layout floating'

[[on-window-detected]]
if.app-id = 'com.apple.archiveutility'
run = 'layout floating'

[[on-window-detected]]
if.app-id = 'com.apple.ScreenSharing'
run = 'layout floating'

# ===========================================================================
# main mode
# ===========================================================================
[mode.main.binding]

    # --- Launchers (Hyprland: SUPER+Return, SUPER+E) ---
    alt-enter = 'exec-and-forget ${TERMINAL_CMD}'
    alt-e     = 'exec-and-forget open -a Finder'

    # --- Window actions (SUPER+Q kill, SUPER+V float, SUPER+F full) ---
    alt-q       = 'close'
    alt-shift-q = 'close-all-windows-but-current'
    alt-v       = 'layout floating tiling'
    alt-f       = 'fullscreen'
    alt-s       = 'layout tiles horizontal vertical'
    alt-comma   = 'layout accordion horizontal vertical'

    # --- Focus (hjkl + arrows, like every Hyprland config) ---
    alt-h = 'focus left'
    alt-j = 'focus down'
    alt-k = 'focus up'
    alt-l = 'focus right'
    alt-left  = 'focus left'
    alt-down  = 'focus down'
    alt-up    = 'focus up'
    alt-right = 'focus right'

    # --- Move window ---
    alt-shift-h = 'move left'
    alt-shift-j = 'move down'
    alt-shift-k = 'move up'
    alt-shift-l = 'move right'
    alt-shift-left  = 'move left'
    alt-shift-down  = 'move down'
    alt-shift-up    = 'move up'
    alt-shift-right = 'move right'

    # --- Resize (Hyprland: SUPER+CTRL+dir) ---
    alt-ctrl-h = 'resize width -50'
    alt-ctrl-j = 'resize height +50'
    alt-ctrl-k = 'resize height -50'
    alt-ctrl-l = 'resize width +50'
    alt-minus  = 'resize smart -50'
    alt-equal  = 'resize smart +50'

    # --- Workspaces ---
    alt-1 = 'workspace 1'
    alt-2 = 'workspace 2'
    alt-3 = 'workspace 3'
    alt-4 = 'workspace 4'
    alt-5 = 'workspace 5'
    alt-6 = 'workspace 6'
    alt-7 = 'workspace 7'
    alt-8 = 'workspace 8'
    alt-9 = 'workspace 9'
    alt-0 = 'workspace 0'

    alt-shift-1 = ['move-node-to-workspace 1', 'workspace 1']
    alt-shift-2 = ['move-node-to-workspace 2', 'workspace 2']
    alt-shift-3 = ['move-node-to-workspace 3', 'workspace 3']
    alt-shift-4 = ['move-node-to-workspace 4', 'workspace 4']
    alt-shift-5 = ['move-node-to-workspace 5', 'workspace 5']
    alt-shift-6 = ['move-node-to-workspace 6', 'workspace 6']
    alt-shift-7 = ['move-node-to-workspace 7', 'workspace 7']
    alt-shift-8 = ['move-node-to-workspace 8', 'workspace 8']
    alt-shift-9 = ['move-node-to-workspace 9', 'workspace 9']
    alt-shift-0 = ['move-node-to-workspace 0', 'workspace 0']

    # Cycle workspaces (Hyprland: SUPER+TAB / mousewheel)
    alt-tab        = 'workspace-back-and-forth'
    alt-ctrl-left  = 'workspace --wrap-around prev'
    alt-ctrl-right = 'workspace --wrap-around next'

    # Multi-monitor
    alt-shift-tab = 'move-workspace-to-monitor --wrap-around next'

    # Keybind cheatsheet (Hyprland configs conventionally bind SUPER+/)
    alt-slash = 'exec-and-forget /bin/bash -lc "open ~/.config/hyprspace/keybinds.html"'

    # Submodes
    alt-shift-semicolon = 'mode service'
    alt-r               = 'mode resize'

# ===========================================================================
# service mode
# ===========================================================================
[mode.service.binding]
    esc       = ['reload-config', 'mode main']
    r         = ['flatten-workspace-tree', 'mode main']
    f         = ['layout floating tiling', 'mode main']
    backspace = ['close-all-windows-but-current', 'mode main']

    h = ['join-with left', 'mode main']
    j = ['join-with down', 'mode main']
    k = ['join-with up', 'mode main']
    l = ['join-with right', 'mode main']

# ===========================================================================
# resize mode (Hyprland's SUPER+R submap)
# ===========================================================================
[mode.resize.binding]
    h = 'resize width -50'
    j = 'resize height +50'
    k = 'resize height -50'
    l = 'resize width +50'
    minus = 'resize smart -50'
    equal = 'resize smart +50'
    enter = 'mode main'
    esc   = 'mode main'
AEROSPACE_TOML

# ===========================================================================
# 6. JankyBorders — the Hyprland gradient glow
# ===========================================================================
step "JankyBorders config"

write_file "$BORDERS_DIR/bordersrc" <<BORDERSRC
#!/usr/bin/env bash
# ~/.config/borders/bordersrc — generated by hyprspace.sh
# Hyprland's signature: a bright gradient on the focused window, a dim
# hairline on everything else. Colors are 0xAARRGGBB.

options=(
  style=round
  width=${BORDER_WIDTH}
  hidpi=on
  active_color="gradient(top_left=0xff${HEX_BLUE},bottom_right=0xff${HEX_MAUVE})"
  inactive_color=0xff${HEX_SURF1}
  background_color=0x00000000
  blacklist="Alfred,Raycast,Spotlight"
)

borders "\${options[@]}"
BORDERSRC
run chmod +x "$BORDERS_DIR/bordersrc"

# ===========================================================================
# 7. Keybind cheatsheet
#
# A self-contained HTML page opened by alt+/ . HTML rather than a dialog or a
# terminal window because it needs no dependency, no terminal emulator, and
# survives having more rows added to it.
# ===========================================================================
step "Cheatsheet"

CHEAT_DIR="$HOME/.config/hyprspace"
write_file "$CHEAT_DIR/keybinds.html" <<CHEATSHEET
<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<title>hyprspace keybinds</title>
<style>
  :root {
    --base:#1e1e2e; --mantle:#181825; --surface:#313244; --overlay:#6c7086;
    --text:#cdd6f4; --subtext:#a6adc8; --blue:#${HEX_BLUE}; --mauve:#${HEX_MAUVE};
  }
  * { box-sizing:border-box; }
  body {
    margin:0; padding:3rem 1.5rem; background:var(--base); color:var(--text);
    font:15px/1.55 "JetBrainsMono Nerd Font","JetBrains Mono",ui-monospace,monospace;
  }
  .wrap { max-width:960px; margin:0 auto; }
  h1 { margin:0 0 .25rem; font-size:1.5rem; font-weight:700;
       background:linear-gradient(100deg,var(--blue),var(--mauve));
       -webkit-background-clip:text; background-clip:text; color:transparent; }
  .sub { color:var(--overlay); margin:0 0 2.5rem; font-size:.875rem; }
  .grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(340px,1fr)); gap:2rem; }
  section { background:var(--mantle); border:1px solid var(--surface);
            border-radius:12px; padding:1.25rem 1.5rem; }
  h2 { margin:0 0 1rem; font-size:.75rem; letter-spacing:.09em;
       text-transform:uppercase; color:var(--mauve); font-weight:600; }
  table { width:100%; border-collapse:collapse; }
  td { padding:.32rem 0; vertical-align:top; }
  td:first-child { white-space:nowrap; padding-right:1.25rem; }
  kbd { display:inline-block; background:var(--surface); color:var(--text);
        border-radius:5px; padding:.1rem .45rem; font-size:.8125rem;
        border-bottom:2px solid #11111b; }
  td:last-child { color:var(--subtext); }
  footer { margin-top:2.5rem; color:var(--overlay); font-size:.8125rem; text-align:center; }
  @media (prefers-color-scheme: light) { /* deliberately dark in both */ }
</style></head><body><div class="wrap">
<h1>hyprspace</h1>
<p class="sub">AeroSpace keybinds — <kbd>alt</kbd> stands in for Hyprland's SUPER</p>
<div class="grid">

<section><h2>Launch &amp; window</h2><table>
<tr><td><kbd>alt</kbd> <kbd>↵</kbd></td><td>terminal</td></tr>
<tr><td><kbd>alt</kbd> <kbd>E</kbd></td><td>Finder</td></tr>
<tr><td><kbd>alt</kbd> <kbd>Q</kbd></td><td>close window</td></tr>
<tr><td><kbd>alt</kbd> <kbd>⇧</kbd> <kbd>Q</kbd></td><td>close all but current</td></tr>
<tr><td><kbd>alt</kbd> <kbd>V</kbd></td><td>toggle floating</td></tr>
<tr><td><kbd>alt</kbd> <kbd>F</kbd></td><td>fullscreen</td></tr>
<tr><td><kbd>alt</kbd> <kbd>S</kbd></td><td>toggle split direction</td></tr>
<tr><td><kbd>alt</kbd> <kbd>,</kbd></td><td>accordion layout</td></tr>
</table></section>

<section><h2>Focus &amp; move</h2><table>
<tr><td><kbd>alt</kbd> <kbd>H</kbd><kbd>J</kbd><kbd>K</kbd><kbd>L</kbd></td><td>focus (arrows work too)</td></tr>
<tr><td><kbd>alt</kbd> <kbd>⇧</kbd> <kbd>H</kbd><kbd>J</kbd><kbd>K</kbd><kbd>L</kbd></td><td>move window</td></tr>
<tr><td><kbd>alt</kbd> <kbd>⌃</kbd> <kbd>H</kbd><kbd>J</kbd><kbd>K</kbd><kbd>L</kbd></td><td>resize</td></tr>
<tr><td><kbd>alt</kbd> <kbd>-</kbd> / <kbd>=</kbd></td><td>shrink / grow</td></tr>
</table></section>

<section><h2>Workspaces</h2><table>
<tr><td><kbd>alt</kbd> <kbd>1</kbd>…<kbd>9</kbd><kbd>0</kbd></td><td>switch workspace</td></tr>
<tr><td><kbd>alt</kbd> <kbd>⇧</kbd> <kbd>1</kbd>…<kbd>0</kbd></td><td>send window there + follow</td></tr>
<tr><td><kbd>alt</kbd> <kbd>⇥</kbd></td><td>last workspace</td></tr>
<tr><td><kbd>alt</kbd> <kbd>⌃</kbd> <kbd>←</kbd>/<kbd>→</kbd></td><td>cycle workspaces</td></tr>
<tr><td><kbd>alt</kbd> <kbd>⇧</kbd> <kbd>⇥</kbd></td><td>workspace to next monitor</td></tr>
</table></section>

<section><h2>Modes &amp; help</h2><table>
<tr><td><kbd>alt</kbd> <kbd>/</kbd></td><td>this cheatsheet</td></tr>
<tr><td><kbd>alt</kbd> <kbd>R</kbd></td><td>resize submap — <kbd>esc</kbd> exits</td></tr>
<tr><td><kbd>alt</kbd> <kbd>⇧</kbd> <kbd>;</kbd></td><td>service mode</td></tr>
<tr><td style="padding-left:1rem">└ <kbd>esc</kbd></td><td>reload config</td></tr>
<tr><td style="padding-left:1rem">└ <kbd>R</kbd></td><td>reset layout</td></tr>
<tr><td style="padding-left:1rem">└ <kbd>F</kbd></td><td>toggle float</td></tr>
<tr><td style="padding-left:1rem">└ <kbd>H</kbd><kbd>J</kbd><kbd>K</kbd><kbd>L</kbd></td><td>join with neighbour</td></tr>
</table></section>

</div>
<footer>~/.aerospace.toml · regenerate with ./hyprspace.sh --configs-only</footer>
</div></body></html>
CHEATSHEET

# ===========================================================================
# 8. Start everything
# ===========================================================================
step "Services"
if (( DRY_RUN )); then
  info "would start: borders, AeroSpace"
else
  brew services restart borders >/dev/null 2>&1 && ok "borders running" \
    || { pkill -x borders 2>/dev/null || true
         ( borders >/dev/null 2>&1 & )
         ok "borders running (foreground launch)"; }

  if pgrep -xq AeroSpace; then
    aerospace reload-config >/dev/null 2>&1 && ok "AeroSpace config reloaded" \
      || warn "AeroSpace running but reload failed — check ~/.aerospace.toml"
  else
    open -a AeroSpace 2>/dev/null && ok "AeroSpace launched" \
      || warn "could not launch AeroSpace — open it from /Applications"
  fi
fi

# ===========================================================================
# 9. Summary
# ===========================================================================
cat <<SUMMARY

${C_B}${C_GRN}Done.${C_RST} ${THEME_NAME}, ${GAP_INNER}px gaps, gradient on the focused window.

${C_B}Permissions${C_RST} — macOS will prompt, and this is required:
  • ${C_B}Accessibility${C_RST} → AeroSpace   (System Settings ▸ Privacy & Security)
  • Grant it, then restart AeroSpace. Nothing tiles until you do.

${C_B}Keybinds${C_RST} ${C_DIM}(ALT stands in for Hyprland's SUPER)${C_RST}
  ${C_BLU}alt + Return${C_RST}        terminal
  ${C_BLU}alt + E${C_RST}             Finder
  ${C_BLU}alt + Q${C_RST}             close window
  ${C_BLU}alt + V${C_RST}             toggle float
  ${C_BLU}alt + F${C_RST}             fullscreen
  ${C_BLU}alt + S${C_RST}             toggle split direction
  ${C_BLU}alt + h/j/k/l${C_RST}       focus            ${C_DIM}(arrows work too)${C_RST}
  ${C_BLU}alt + shift + hjkl${C_RST}  move window
  ${C_BLU}alt + ctrl + hjkl${C_RST}   resize
  ${C_BLU}alt + 1..9,0${C_RST}        switch workspace
  ${C_BLU}alt + shift + 1..0${C_RST}  send window to workspace + follow
  ${C_BLU}alt + Tab${C_RST}           last workspace
  ${C_BLU}alt + R${C_RST}             resize submap    ${C_DIM}(Esc to exit)${C_RST}
  ${C_BLU}alt + shift + ;${C_RST}     service mode     ${C_DIM}(Esc reloads config)${C_RST}
  ${C_BLU}alt + /${C_RST}             ${C_B}show this cheatsheet${C_RST}

${C_B}Retheme${C_RST}   edit the PALETTE block at the top of this script, rerun with
           ${C_DIM}./$(basename "$0") --configs-only${C_RST}

${C_B}Files${C_RST}     ~/.aerospace.toml
           ~/.config/borders/bordersrc
           ~/.config/hyprspace/keybinds.html
SUMMARY

if (( DO_BACKUP )) && [[ -d "$BACKUP_DIR" ]]; then
  printf '%s\n' "${C_B}Backup${C_RST}    ${BACKUP_DIR/#$HOME/\~}"
fi
printf '\n'
