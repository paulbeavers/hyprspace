#!/usr/bin/env bash
# ============================================================================
#  hyprspace.sh — make macOS + AeroSpace look and behave like Hyprland
# ============================================================================
#
#  One self-contained, idempotent, re-runnable script. Copy it to any Mac and
#  run it; it installs everything and writes every config file itself.
#
#    curl -fsSL <your-url>/hyprspace.sh -o hyprspace.sh
#    bash hyprspace.sh
#
#  What it sets up
#    AeroSpace      tiling WM        <- the i3/Hyprland core
#    JankyBorders   gradient borders <- Hyprland's animated border glow
#    SketchyBar     top status bar   <- Waybar
#    JetBrainsMono Nerd Font + sketchybar-app-font
#
#  Theme: Catppuccin Mocha (edit the PALETTE block below to retheme everything)
#
#  Flags
#    --dry-run        print what would happen, touch nothing
#    --configs-only   skip Homebrew/package installation, just rewrite configs
#    --no-backup      don't back up existing configs (default: always back up)
#    --keep-menubar   don't auto-hide the macOS menu bar (see note below)
#    -h | --help
#
# ============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# PALETTE — Catppuccin Mocha. Single source of truth for every generated file.
# sketchybar/borders want 0xAARRGGBB; kitty/others want #RRGGBB.
# ---------------------------------------------------------------------------
THEME_NAME="Catppuccin Mocha"

HEX_BASE="1e1e2e";  HEX_MANTLE="181825"; HEX_CRUST="11111b"
HEX_SURF0="313244"; HEX_SURF1="45475a";  HEX_SURF2="585b70"
HEX_OVER0="6c7086"; HEX_SUB0="a6adc8";   HEX_TEXT="cdd6f4"
HEX_BLUE="89b4fa";  HEX_LAVENDER="b4befe"; HEX_MAUVE="cba6f7"
HEX_GREEN="a6e3a1"; HEX_TEAL="94e2d5";   HEX_SKY="89dceb"
HEX_YELLOW="f9e2af"; HEX_PEACH="fab387"; HEX_RED="f38ba8"
HEX_PINK="f5c2e7";  HEX_MAROON="eba0ac"

# Bar geometry. AeroSpace's top gap is derived from these so windows never
# slide under the bar.
BAR_HEIGHT=36
BAR_Y_OFFSET=6
BAR_MARGIN=10
GAP_INNER=10

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
DRY_RUN=0
CONFIGS_ONLY=0
DO_BACKUP=1
HIDE_MENUBAR=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)      DRY_RUN=1 ;;
    --configs-only) CONFIGS_ONLY=1 ;;
    --no-backup)    DO_BACKUP=0 ;;
    --keep-menubar) HIDE_MENUBAR=0 ;;
    -h|--help)      sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

# ---------------------------------------------------------------------------
# Derived values
# ---------------------------------------------------------------------------
GAP_TOP=$(( BAR_HEIGHT + BAR_Y_OFFSET + GAP_INNER ))
SKETCHY_DIR="$HOME/.config/sketchybar"
BORDERS_DIR="$HOME/.config/borders"
AERO_CONF="$HOME/.aerospace.toml"
BACKUP_DIR="$HOME/.hyprspace-backup/$(date +%Y%m%d-%H%M%S)"

printf '\n%s%s  hyprspace%s  %s— AeroSpace, dressed as Hyprland%s\n' \
  "$C_B" "$C_BLU" "$C_RST" "$C_DIM" "$C_RST"
printf '  %stheme: %s   bar: %spx   gaps: %s/%s%s\n' \
  "$C_DIM" "$THEME_NAME" "$BAR_HEIGHT" "$GAP_INNER" "$GAP_TOP" "$C_RST"
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
      info "$C_DIM\$ NONINTERACTIVE=1 bash -c \"\$(curl -fsSL $HOMEBREW_INSTALLER)\"$C_RST"
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
  have_formula() { brew list --formula --versions "$1" >/dev/null 2>&1; }
  have_cask()    { brew list --cask    --versions "$1" >/dev/null 2>&1; }

  install_formula() {
    if have_formula "$1"; then ok "$1 (already installed)"
    else info "installing $1…"; run brew install "$1" && ok "$1"; fi
  }
  install_cask() {
    if have_cask "$1"; then ok "$1 (already installed)"
    else info "installing $1…"; run brew install --cask "$1" && ok "$1"; fi
  }

  install_cask    nikitabobko/tap/aerospace
  install_formula FelixKratz/formulae/sketchybar
  install_formula FelixKratz/formulae/borders
  install_formula jq
  install_cask    font-jetbrains-mono-nerd-font
  install_cask    font-sketchybar-app-font
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
  info "for the real look: brew install --cask kitty  (then rerun this script)"
fi

# ===========================================================================
# 4. Back up whatever is already there
# ===========================================================================
if (( DO_BACKUP )); then
  step "Backup"
  backed_up=0
  for target in "$AERO_CONF" "$SKETCHY_DIR" "$BORDERS_DIR"; do
    if [[ -e "$target" ]]; then
      run mkdir -p "$BACKUP_DIR"
      run cp -R "$target" "$BACKUP_DIR/"
      ok "saved ${target/#$HOME/\~}"
      backed_up=1
    fi
  done
  if (( backed_up )); then
    info "backup: ${BACKUP_DIR/#$HOME/\~}"
  else
    info "nothing to back up (clean machine)"
  fi
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

# Hyprland-style numbered workspaces, always present in the bar.
persistent-workspaces = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

# --- Gaps -------------------------------------------------------------------
# outer.top clears the floating SketchyBar (${BAR_HEIGHT}px bar + ${BAR_Y_OFFSET}px offset + ${GAP_INNER}px gap).
gaps.inner.horizontal = ${GAP_INNER}
gaps.inner.vertical   = ${GAP_INNER}
gaps.outer.top        = ${GAP_TOP}
gaps.outer.bottom     = ${BAR_MARGIN}
gaps.outer.left       = ${BAR_MARGIN}
gaps.outer.right      = ${BAR_MARGIN}

# --- Startup ----------------------------------------------------------------
after-startup-command = [
  'exec-and-forget /bin/bash -lc "command -v borders >/dev/null && borders &"',
  'exec-and-forget /bin/bash -lc "command -v sketchybar >/dev/null && sketchybar --reload"',
]

# Push the focused workspace into SketchyBar on every change.
exec-on-workspace-change = [
  '/bin/bash', '-c',
  'sketchybar --trigger aerospace_workspace_change FOCUSED_WORKSPACE=\$AEROSPACE_FOCUSED_WORKSPACE',
]

# Unlike exec-on-workspace-change (a raw argv array), on-mode-changed takes
# AeroSpace commands — so the shell call has to go through exec-and-forget.
# The plugin reads the mode itself via 'aerospace list-modes --current';
# there is no documented AEROSPACE_MODE env var to rely on.
on-mode-changed = [
  'exec-and-forget /bin/bash -c "sketchybar --trigger aerospace_mode_change"',
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
    alt-slash   = 'layout tiles horizontal vertical'
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

    # Cycle workspaces (Hyprland: SUPER+mousewheel / SUPER+TAB)
    alt-tab       = 'workspace-back-and-forth'
    alt-ctrl-left  = 'workspace --wrap-around prev'
    alt-ctrl-right = 'workspace --wrap-around next'

    # Multi-monitor
    alt-shift-tab = 'move-workspace-to-monitor --wrap-around next'

    # Service / resize submode
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
  width=5.0
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
# 7. SketchyBar — the Waybar clone
# ===========================================================================
step "SketchyBar config"

# --- colors.sh -------------------------------------------------------------
write_file "$SKETCHY_DIR/colors.sh" <<COLORS
#!/usr/bin/env bash
# ${THEME_NAME} — generated by hyprspace.sh. 0xAARRGGBB.

export BASE=0xff${HEX_BASE}
export MANTLE=0xff${HEX_MANTLE}
export CRUST=0xff${HEX_CRUST}
export SURFACE0=0xff${HEX_SURF0}
export SURFACE1=0xff${HEX_SURF1}
export SURFACE2=0xff${HEX_SURF2}
export OVERLAY0=0xff${HEX_OVER0}
export SUBTEXT0=0xff${HEX_SUB0}
export TEXT=0xff${HEX_TEXT}
export BLUE=0xff${HEX_BLUE}
export LAVENDER=0xff${HEX_LAVENDER}
export MAUVE=0xff${HEX_MAUVE}
export GREEN=0xff${HEX_GREEN}
export TEAL=0xff${HEX_TEAL}
export SKY=0xff${HEX_SKY}
export YELLOW=0xff${HEX_YELLOW}
export PEACH=0xff${HEX_PEACH}
export RED=0xff${HEX_RED}
export PINK=0xff${HEX_PINK}
export MAROON=0xff${HEX_MAROON}

# Semantic roles
export BAR_COLOR=0xf0${HEX_BASE}          # slightly translucent, like a Waybar
export BAR_BORDER_COLOR=0xff${HEX_SURF0}
export ITEM_BG=0xff${HEX_SURF0}
export ACCENT=\$LAVENDER
export TRANSPARENT=0x00000000
COLORS

# --- sketchybarrc ----------------------------------------------------------
write_file "$SKETCHY_DIR/sketchybarrc" <<SKETCHYBARRC
#!/usr/bin/env bash
# ~/.config/sketchybar/sketchybarrc — generated by hyprspace.sh

export CONFIG_DIR="\$HOME/.config/sketchybar"
export PLUGIN_DIR="\$CONFIG_DIR/plugins"
source "\$CONFIG_DIR/colors.sh"

FONT="JetBrainsMono Nerd Font"

# --- bar: a floating, rounded Waybar --------------------------------------
sketchybar --bar \\
  height=${BAR_HEIGHT} \\
  position=top \\
  sticky=on \\
  padding_left=8 \\
  padding_right=8 \\
  margin=${BAR_MARGIN} \\
  y_offset=${BAR_Y_OFFSET} \\
  corner_radius=12 \\
  border_width=2 \\
  border_color=\$BAR_BORDER_COLOR \\
  color=\$BAR_COLOR \\
  shadow=on \\
  blur_radius=30 \\
  notch_width=200 \\
  topmost=window

# --- defaults --------------------------------------------------------------
sketchybar --default \\
  updates=when_shown \\
  icon.font="\$FONT:Bold:14.0" \\
  icon.color=\$TEXT \\
  icon.padding_left=8 \\
  icon.padding_right=4 \\
  label.font="\$FONT:Semibold:13.0" \\
  label.color=\$TEXT \\
  label.padding_left=4 \\
  label.padding_right=8 \\
  background.corner_radius=8 \\
  background.height=26 \\
  background.drawing=off \\
  padding_left=3 \\
  padding_right=3

# --- events ----------------------------------------------------------------
sketchybar --add event aerospace_workspace_change
sketchybar --add event aerospace_mode_change

# ===========================================================================
# LEFT — workspace pills + focused app
# ===========================================================================
WORKSPACES=(1 2 3 4 5 6 7 8 9 0)

for sid in "\${WORKSPACES[@]}"; do
  sketchybar --add item space.\$sid left \\
             --set space.\$sid \\
                   icon="\$sid" \\
                   icon.font="\$FONT:Bold:13.0" \\
                   icon.padding_left=9 \\
                   icon.padding_right=9 \\
                   label.drawing=off \\
                   background.drawing=on \\
                   background.color=\$TRANSPARENT \\
                   background.height=24 \\
                   background.corner_radius=7 \\
                   click_script="aerospace workspace \$sid"
done

# One observer drives every pill in a single batched update — far cheaper
# than giving each pill its own script process.
sketchybar --add item spaces_observer left \\
           --set spaces_observer \\
                 drawing=off \\
                 updates=on \\
                 script="\$PLUGIN_DIR/workspaces.sh" \\
           --subscribe spaces_observer aerospace_workspace_change \\
                                       front_app_switched \\
                                       space_windows_change

sketchybar --add item mode left \\
           --set mode \\
                 drawing=off \\
                 icon.drawing=off \\
                 label.color=\$PEACH \\
                 background.drawing=on \\
                 background.color=\$SURFACE0 \\
                 script="\$PLUGIN_DIR/mode.sh" \\
           --subscribe mode aerospace_mode_change

sketchybar --add item front_app left \\
           --set front_app \\
                 icon.font="sketchybar-app-font:Regular:15.0" \\
                 icon.color=\$LAVENDER \\
                 label.color=\$SUBTEXT0 \\
                 label.max_chars=40 \\
                 padding_left=10 \\
                 script="\$PLUGIN_DIR/front_app.sh" \\
           --subscribe front_app front_app_switched

# ===========================================================================
# CENTER — clock
# ===========================================================================
sketchybar --add item clock center \\
           --set clock \\
                 update_freq=10 \\
                 icon="󰥔" \\
                 icon.color=\$MAUVE \\
                 label.color=\$TEXT \\
                 background.drawing=on \\
                 background.color=\$SURFACE0 \\
                 script="\$PLUGIN_DIR/clock.sh"

# ===========================================================================
# RIGHT — status modules (rightmost item is added first)
# ===========================================================================
sketchybar --add item battery right \\
           --set battery \\
                 update_freq=120 \\
                 script="\$PLUGIN_DIR/battery.sh" \\
           --subscribe battery power_source_change system_woke

sketchybar --add item volume right \\
           --set volume \\
                 script="\$PLUGIN_DIR/volume.sh" \\
           --subscribe volume volume_change

sketchybar --add item wifi right \\
           --set wifi \\
                 update_freq=15 \\
                 script="\$PLUGIN_DIR/wifi.sh" \\
           --subscribe wifi wifi_change system_woke

sketchybar --add item cpu right \\
           --set cpu \\
                 update_freq=5 \\
                 icon="󰘚" \\
                 icon.color=\$TEAL \\
                 script="\$PLUGIN_DIR/cpu.sh"

sketchybar --add item memory right \\
           --set memory \\
                 update_freq=10 \\
                 icon="󰍛" \\
                 icon.color=\$SKY \\
                 script="\$PLUGIN_DIR/memory.sh"

# --- go --------------------------------------------------------------------
sketchybar --hotload on
sketchybar --update
SKETCHYBARRC
run chmod +x "$SKETCHY_DIR/sketchybarrc"

# --- plugins ---------------------------------------------------------------
info "writing plugins…"

write_file "$SKETCHY_DIR/plugins/workspaces.sh" <<'PLUG_WS'
#!/usr/bin/env bash
# Repaint every workspace pill in one batched sketchybar call.
source "${CONFIG_DIR:-$HOME/.config/sketchybar}/colors.sh"

WORKSPACES=(1 2 3 4 5 6 7 8 9 0)

FOCUSED="${FOCUSED_WORKSPACE:-}"
[ -z "$FOCUSED" ] && FOCUSED="$(aerospace list-workspaces --focused 2>/dev/null)"

# One call for all windows; count per workspace locally.
OCCUPIED=" $(aerospace list-windows --all --format '%{workspace}' 2>/dev/null \
             | sort -u | tr '\n' ' ')"

args=()
for sid in "${WORKSPACES[@]}"; do
  if [ "$sid" = "$FOCUSED" ]; then
    # active: filled lavender pill, dark text — Hyprland's current workspace
    args+=(--set "space.$sid" background.color="$LAVENDER" \
                              background.drawing=on \
                              icon.color="$BASE")
  elif [[ "$OCCUPIED" == *" $sid "* ]]; then
    # occupied: muted pill
    args+=(--set "space.$sid" background.color="$SURFACE0" \
                              background.drawing=on \
                              icon.color="$TEXT")
  else
    # empty: bare, dimmed number
    args+=(--set "space.$sid" background.drawing=off \
                              icon.color="$OVERLAY0")
  fi
done

sketchybar "${args[@]}"
PLUG_WS

write_file "$SKETCHY_DIR/plugins/front_app.sh" <<'PLUG_APP'
#!/usr/bin/env bash
source "${CONFIG_DIR:-$HOME/.config/sketchybar}/colors.sh"

if [ "$SENDER" = "front_app_switched" ]; then
  icon=":default:"
  ICON_MAP="${PLUGIN_DIR:-$HOME/.config/sketchybar/plugins}/icon_map.sh"
  if [ -f "$ICON_MAP" ]; then
    source "$ICON_MAP"
    __icon_map "$INFO"
    icon="$icon_result"
  fi
  sketchybar --set "$NAME" icon="$icon" label="$INFO"
fi
PLUG_APP

write_file "$SKETCHY_DIR/plugins/mode.sh" <<'PLUG_MODE'
#!/usr/bin/env bash
# Badge shown while AeroSpace is in a non-main binding mode (service/resize),
# like Hyprland's submap indicator.
MODE="$(aerospace list-modes --current 2>/dev/null)"

if [ -z "$MODE" ] || [ "$MODE" = "main" ]; then
  sketchybar --set "$NAME" drawing=off
else
  sketchybar --set "$NAME" drawing=on label="-- ${MODE} --"
fi
PLUG_MODE

write_file "$SKETCHY_DIR/plugins/clock.sh" <<'PLUG_CLOCK'
#!/usr/bin/env bash
sketchybar --set "$NAME" label="$(date '+%a %d %b  %H:%M')"
PLUG_CLOCK

write_file "$SKETCHY_DIR/plugins/battery.sh" <<'PLUG_BATT'
#!/usr/bin/env bash
source "${CONFIG_DIR:-$HOME/.config/sketchybar}/colors.sh"

BATT="$(pmset -g batt)"
PCT="$(printf '%s' "$BATT" | grep -Eo '[0-9]+%' | head -1 | tr -d '%')"
[ -z "$PCT" ] && { sketchybar --set "$NAME" drawing=off; exit 0; }

CHARGING=0
printf '%s' "$BATT" | grep -q "AC Power" && CHARGING=1

if [ "$CHARGING" -eq 1 ]; then
  ICON="󰂄"; COLOR="$GREEN"
else
  case "${PCT}" in
    100|9[0-9]) ICON="󰁹"; COLOR="$GREEN"  ;;
    8[0-9]|7[0-9]) ICON="󰂀"; COLOR="$GREEN"  ;;
    6[0-9]|5[0-9]) ICON="󰁿"; COLOR="$TEAL"   ;;
    4[0-9]|3[0-9]) ICON="󰁾"; COLOR="$YELLOW" ;;
    2[0-9])        ICON="󰁻"; COLOR="$PEACH"  ;;
    *)             ICON="󰂎"; COLOR="$RED"    ;;
  esac
fi

sketchybar --set "$NAME" drawing=on icon="$ICON" icon.color="$COLOR" label="${PCT}%"
PLUG_BATT

write_file "$SKETCHY_DIR/plugins/volume.sh" <<'PLUG_VOL'
#!/usr/bin/env bash
source "${CONFIG_DIR:-$HOME/.config/sketchybar}/colors.sh"

VOL="$INFO"
if [ -z "$VOL" ]; then
  VOL="$(osascript -e 'output volume of (get volume settings)' 2>/dev/null)"
  MUTED="$(osascript -e 'output muted of (get volume settings)' 2>/dev/null)"
  [ "$MUTED" = "true" ] && VOL=0
fi

case "$VOL" in
  ''|*[!0-9]*) exit 0 ;;
esac

if   [ "$VOL" -eq 0 ];  then ICON="󰝟"; COLOR="$OVERLAY0"
elif [ "$VOL" -lt 34 ]; then ICON="󰕿"; COLOR="$SKY"
elif [ "$VOL" -lt 67 ]; then ICON="󰖀"; COLOR="$SKY"
else                         ICON="󰕾"; COLOR="$SKY"
fi

sketchybar --set "$NAME" icon="$ICON" icon.color="$COLOR" label="${VOL}%"
PLUG_VOL

write_file "$SKETCHY_DIR/plugins/wifi.sh" <<'PLUG_WIFI'
#!/usr/bin/env bash
# Connectivity indicator. Deliberately avoids reading the SSID — on modern
# macOS that requires a Location Services grant and silently returns empty.
source "${CONFIG_DIR:-$HOME/.config/sketchybar}/colors.sh"

IFACE="$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')"

if [ -z "$IFACE" ]; then
  sketchybar --set "$NAME" icon="󰤭" icon.color="$RED" label="offline"
  exit 0
fi

if networksetup -listallhardwareports 2>/dev/null \
   | grep -A1 "Wi-Fi" | grep -q "Device: $IFACE"; then
  sketchybar --set "$NAME" icon="󰖩" icon.color="$BLUE" label="Wi-Fi"
else
  sketchybar --set "$NAME" icon="󰈀" icon.color="$BLUE" label="LAN"
fi
PLUG_WIFI

write_file "$SKETCHY_DIR/plugins/cpu.sh" <<'PLUG_CPU'
#!/usr/bin/env bash
# Cheap CPU read: sum of per-process %CPU over core count. `top -l 2` would
# block for a full sample interval on every tick.
source "${CONFIG_DIR:-$HOME/.config/sketchybar}/colors.sh"

CORES="$(sysctl -n hw.ncpu)"
USAGE="$(ps -A -o %cpu | awk -v c="$CORES" 'NR>1{s+=$1} END {printf "%d", (c>0 ? s/c : 0)}')"
[ "$USAGE" -gt 100 ] && USAGE=100

if   [ "$USAGE" -ge 80 ]; then COLOR="$RED"
elif [ "$USAGE" -ge 50 ]; then COLOR="$PEACH"
else                           COLOR="$TEAL"
fi

sketchybar --set "$NAME" label="${USAGE}%" label.color="$COLOR"
PLUG_CPU

write_file "$SKETCHY_DIR/plugins/memory.sh" <<'PLUG_MEM'
#!/usr/bin/env bash
# Memory pressure — closer to what macOS actually reports than free-page math.
source "${CONFIG_DIR:-$HOME/.config/sketchybar}/colors.sh"

USED="$(memory_pressure 2>/dev/null \
        | awk -F': ' '/System-wide memory free percentage/{gsub(/%/,"",$2); printf "%d", 100-$2}')"
[ -z "$USED" ] && USED=0

if   [ "$USED" -ge 85 ]; then COLOR="$RED"
elif [ "$USED" -ge 65 ]; then COLOR="$PEACH"
else                          COLOR="$SKY"
fi

sketchybar --set "$NAME" label="${USED}%" label.color="$COLOR"
PLUG_MEM

if ! (( DRY_RUN )); then
  chmod +x "$SKETCHY_DIR"/plugins/*.sh
  ok "plugins made executable"
fi

# --- app icon map ----------------------------------------------------------
step "App icon map"
ICON_MAP="$SKETCHY_DIR/plugins/icon_map.sh"
# Shipped as a release asset, not committed to the repo tree.
ICON_MAP_URL="https://github.com/kvndrsslr/sketchybar-app-font/releases/latest/download/icon_map.sh"
if (( DRY_RUN )); then
  info "would download $ICON_MAP_URL"
elif curl -fsSL --max-time 30 "$ICON_MAP_URL" -o "$ICON_MAP".tmp 2>/dev/null \
     && grep -q "__icon_map" "$ICON_MAP".tmp; then
  mv "$ICON_MAP".tmp "$ICON_MAP"
  chmod +x "$ICON_MAP"
  ok "icon_map.sh (app glyphs in the bar)"
else
  rm -f "$ICON_MAP".tmp
  warn "could not fetch icon_map.sh — front_app will show a generic glyph"
  cat > "$ICON_MAP" <<'FALLBACK'
#!/usr/bin/env bash
__icon_map() { icon_result=":default:"; }
FALLBACK
  chmod +x "$ICON_MAP"
fi

# ===========================================================================
# 8. Menu bar
# ===========================================================================
step "macOS menu bar"
if (( HIDE_MENUBAR )); then
  # Without this you get two stacked bars. Reversible in
  # System Settings > Control Center > Automatically hide and show the menu bar.
  run defaults write NSGlobalDomain _HIHideMenuBar -bool true
  ok "auto-hide enabled (undo: defaults write NSGlobalDomain _HIHideMenuBar -bool false)"
else
  warn "left visible (--keep-menubar) — it will sit above the SketchyBar"
fi

# ===========================================================================
# 9. Start everything
# ===========================================================================
step "Services"
if (( DRY_RUN )); then
  info "would start: sketchybar, borders, AeroSpace"
else
  brew services restart sketchybar >/dev/null 2>&1 && ok "sketchybar running" \
    || warn "could not start sketchybar via brew services"

  brew services restart borders >/dev/null 2>&1 && ok "borders running" \
    || { pkill -x borders 2>/dev/null || true; ( borders >/dev/null 2>&1 & ) ; ok "borders running (foreground launch)"; }

  if pgrep -xq AeroSpace; then
    aerospace reload-config >/dev/null 2>&1 && ok "AeroSpace config reloaded" \
      || warn "AeroSpace running but reload failed — check ~/.aerospace.toml"
  else
    open -a AeroSpace 2>/dev/null && ok "AeroSpace launched" \
      || warn "could not launch AeroSpace — open it from /Applications"
  fi
fi

# ===========================================================================
# 10. Summary
# ===========================================================================
cat <<SUMMARY

${C_B}${C_GRN}Done.${C_RST} ${THEME_NAME}, ${GAP_INNER}px gaps, gradient borders, floating bar.

${C_B}Permissions${C_RST} — macOS will prompt; both are required:
  • ${C_B}Accessibility${C_RST} → AeroSpace   (System Settings ▸ Privacy & Security)
  • Grant, then restart AeroSpace. Nothing tiles until you do.

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

${C_B}Retheme${C_RST}   edit the PALETTE block at the top of this script, rerun with
           ${C_DIM}bash $(basename "$0") --configs-only${C_RST}

${C_B}Files${C_RST}     ~/.aerospace.toml
           ~/.config/sketchybar/{sketchybarrc,colors.sh,plugins/}
           ~/.config/borders/bordersrc
SUMMARY

if (( DO_BACKUP )) && [[ -d "$BACKUP_DIR" ]]; then
  printf '%s\n' "${C_B}Backup${C_RST}    ${BACKUP_DIR/#$HOME/\~}"
fi
printf '\n'
