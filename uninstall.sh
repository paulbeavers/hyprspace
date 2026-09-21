#!/usr/bin/env bash
# ============================================================================
#  uninstall.sh — undo everything hyprspace.sh did
# ============================================================================
#
#    ./uninstall.sh              # remove packages + configs (asks first)
#    ./uninstall.sh --dry-run    # show the plan, change nothing
#    ./uninstall.sh --restore    # also put the original config back
#
#  Flags
#    --dry-run         print every action, change nothing
#    -y | --yes        don't ask for confirmation
#    --restore         restore the ORIGINAL pre-hyprspace config from the
#                      oldest backup, instead of just deleting ours
#    --keep-packages   leave Homebrew packages installed, remove configs only
#    --keep-configs    remove packages only, leave config files in place
#    --keep-font       don't remove JetBrainsMono Nerd Font
#    --untap           also remove the Homebrew taps (see the warning below)
#    --purge-backups   delete ~/.hyprspace-backup entirely when finished
#    -h | --help
#
#  This also cleans up artefacts from earlier versions of hyprspace that used
#  SketchyBar and hid the macOS menu bar, so running it on a machine set up by
#  an older revision still leaves no residue.
#
# ============================================================================

set -euo pipefail

DRY_RUN=0
ASSUME_YES=0
RESTORE=0
KEEP_PACKAGES=0
KEEP_CONFIGS=0
KEEP_FONT=0
UNTAP=0
PURGE_BACKUPS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)       DRY_RUN=1 ;;
    -y|--yes)        ASSUME_YES=1 ;;
    --restore)       RESTORE=1 ;;
    --keep-packages) KEEP_PACKAGES=1 ;;
    --keep-configs)  KEEP_CONFIGS=1 ;;
    --keep-font)     KEEP_FONT=1 ;;
    --untap)         UNTAP=1 ;;
    --purge-backups) PURGE_BACKUPS=1 ;;
    -h|--help)       sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
skip() { printf '    %s·%s %s\n' "$C_DIM" "$C_RST" "$*"; }

BACKUP_ROOT="$HOME/.hyprspace-backup"
AERO_CONF="$HOME/.aerospace.toml"
BORDERS_DIR="$HOME/.config/borders"
# Left behind by earlier hyprspace revisions.
SKETCHY_DIR="$HOME/.config/sketchybar"
HELPER_DIR="$HOME/.config/hyprspace"

printf '\n%s%s  hyprspace uninstall%s\n' "$C_B" "$C_BLU" "$C_RST"
(( DRY_RUN )) && printf '  %s[dry run — nothing will be modified]%s\n' "$C_YEL" "$C_RST"

if ! command -v brew >/dev/null 2>&1; then
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [[ -x "$candidate" ]] && eval "$("$candidate" shellenv)" && break
  done
fi

# ---------------------------------------------------------------------------
# Confirm — this removes software and deletes files.
# ---------------------------------------------------------------------------
if ! (( ASSUME_YES )) && ! (( DRY_RUN )); then
  cat <<PLAN

This will:
  • quit AeroSpace and stop JankyBorders
  • uninstall aerospace, borders$( (( KEEP_FONT )) || printf '%s' ', JetBrainsMono Nerd Font')
  • delete ~/.aerospace.toml and ~/.config/borders
  • restore the macOS menu bar settings hyprspace may have changed
  • clean up SketchyBar leftovers from older hyprspace versions
$( (( RESTORE )) && printf '%s\n' '  • restore your ORIGINAL config from the oldest backup')
$( (( UNTAP )) && printf '%s\n' '  • remove the nikitabobko/tap and FelixKratz/formulae taps')
$( (( PURGE_BACKUPS )) && printf '%s\n' '  • delete ~/.hyprspace-backup and everything in it')
PLAN
  printf '\nProceed? [y/N] '
  read -r reply
  [[ "$reply" =~ ^[Yy] ]] || { printf '\nAborted. Nothing was changed.\n\n'; exit 0; }
fi

# ===========================================================================
# 1. Stop everything first
# ===========================================================================
step "Stopping processes"

# borders may have been started by brew services or straight from AeroSpace,
# so stop the service AND kill any stray process.
stop_service() {   # $1 = brew service name
  command -v brew >/dev/null 2>&1 || return 0
  brew services list 2>/dev/null | grep -q "^$1" || return 0
  if (( DRY_RUN )); then info "would stop the $1 service"; return 0; fi
  brew services stop "$1" >/dev/null 2>&1 && ok "$1 service stopped" \
    || warn "could not stop the $1 service"
}
stop_service borders
stop_service sketchybar

for proc in borders sketchybar; do
  if ! pgrep -xq "$proc" 2>/dev/null; then skip "$proc not running"; continue; fi
  if (( DRY_RUN )); then info "would stop $proc"; continue; fi
  pkill -x "$proc" 2>/dev/null || true
  ok "$proc stopped"
done

if ! pgrep -xq AeroSpace 2>/dev/null; then
  skip "AeroSpace not running"
elif (( DRY_RUN )); then
  info "would quit AeroSpace"
else
  # Ask it to quit so it can tear down cleanly; fall back to a signal.
  osascript -e 'tell application "AeroSpace" to quit' >/dev/null 2>&1 \
    || pkill -x AeroSpace 2>/dev/null || true
  ok "AeroSpace quit"
fi

# ===========================================================================
# 2. macOS settings hyprspace may have changed
# ===========================================================================
step "macOS settings"

# Older revisions hid the menu bar and left these keys behind. Deleting a key
# restores the system default, which is cleaner than guessing the value.
if (( DRY_RUN )); then
  info "would clear _HIHideMenuBar / AppleMenuBarVisibleInFullscreen / AutoHideMenuBarOption"
else
  changed=0
  for key in _HIHideMenuBar AppleMenuBarVisibleInFullscreen; do
    if defaults read NSGlobalDomain "$key" >/dev/null 2>&1; then
      defaults delete NSGlobalDomain "$key" >/dev/null 2>&1 || true
      changed=1
    fi
  done
  if defaults read com.apple.controlcenter AutoHideMenuBarOption >/dev/null 2>&1; then
    defaults delete com.apple.controlcenter AutoHideMenuBarOption >/dev/null 2>&1 || true
    changed=1
  fi
  (( changed )) && ok "menu bar settings reset to macOS defaults" \
                || skip "menu bar settings already at defaults"
fi

# The live autohide flag is WindowServer state, not a preference — clear it
# directly so the menu bar comes back without a logout.
if [[ -x "$HELPER_DIR/hyprspace-menubar" ]]; then
  if (( DRY_RUN )); then
    info "would show the menu bar via the legacy helper"
  else
    "$HELPER_DIR/hyprspace-menubar" --show >/dev/null 2>&1 || true
    ok "menu bar shown via the legacy helper"
  fi
elif command -v swift >/dev/null 2>&1 && ! (( DRY_RUN )); then
  SHOW_SRC="$(mktemp -t hyprspace_show).swift"
  cat > "$SHOW_SRC" <<'SWIFT'
import Foundation
if let h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
   let pc = dlsym(h, "SLSMainConnectionID"),
   let pa = dlsym(h, "SLSSetMenuBarAutohideEnabled") {
  typealias MainConnFn = @convention(c) () -> Int32
  typealias SetAutoFn  = @convention(c) (Int32, Bool) -> Int32
  _ = unsafeBitCast(pa, to: SetAutoFn.self)(unsafeBitCast(pc, to: MainConnFn.self)(), false)
}
SWIFT
  swift "$SHOW_SRC" >/dev/null 2>&1 && ok "menu bar autohide cleared" || skip "menu bar autohide already off"
  rm -f "$SHOW_SRC"
fi

# ===========================================================================
# 3. Packages
# ===========================================================================
if (( KEEP_PACKAGES )); then
  step "Packages"; info "skipped (--keep-packages)"
elif ! command -v brew >/dev/null 2>&1; then
  step "Packages"; warn "Homebrew not found — skipping package removal"
else
  step "Packages"

  # $1 = --formula | --cask, $2 = name
  uninstall_pkg() {
    if ! brew list "$1" --versions "$2" >/dev/null 2>&1; then
      skip "$2 (not installed)"; return 0
    fi
    if (( DRY_RUN )); then info "would remove $2"; return 0; fi
    brew uninstall "$1" "$2" >/dev/null 2>&1 && ok "$2 removed" || warn "could not remove $2"
  }
  uninstall_formula() { uninstall_pkg --formula "$1"; }
  uninstall_cask()    { uninstall_pkg --cask    "$1"; }

  uninstall_cask    aerospace
  uninstall_formula borders
  # Installed by older revisions.
  uninstall_formula sketchybar
  uninstall_cask    font-sketchybar-app-font

  if (( KEEP_FONT )); then
    skip "font-jetbrains-mono-nerd-font (--keep-font)"
  else
    uninstall_cask font-jetbrains-mono-nerd-font
  fi

  if (( UNTAP )); then
    # Only untap when nothing else is left installed from that tap, otherwise
    # Homebrew loses the formula definition for packages still on the system.
    for tap in nikitabobko/tap FelixKratz/formulae; do
      if ! brew tap | grep -qix "$tap"; then
        skip "$tap (not tapped)"
        continue
      fi
      remaining="$(brew list --full-name 2>/dev/null | grep -c "^${tap}/" || true)"
      if [[ "$remaining" -gt 0 ]]; then
        warn "$tap kept — $remaining package(s) from it are still installed"
      elif (( DRY_RUN )); then
        info "would untap $tap"
      else
        brew untap "$tap" >/dev/null 2>&1 && ok "$tap untapped" || warn "could not untap $tap"
      fi
    done
  fi
fi

# ===========================================================================
# 4. Config files
# ===========================================================================
if (( KEEP_CONFIGS )); then
  step "Config files"; info "skipped (--keep-configs)"
else
  step "Config files"
  for target in "$AERO_CONF" "$BORDERS_DIR" "$SKETCHY_DIR" "$HELPER_DIR"; do
    if [[ ! -e "$target" ]]; then
      skip "${target/#$HOME/\~} (absent)"
    elif (( DRY_RUN )); then
      info "would remove ${target/#$HOME/\~}"
    else
      rm -rf "$target"
      ok "removed ${target/#$HOME/\~}"
    fi
  done
fi

# ===========================================================================
# 5. Restore the original config
# ===========================================================================
if (( RESTORE )); then
  step "Restore original config"
  # The OLDEST backup is the true pre-hyprspace state; later ones are just
  # snapshots of hyprspace configs from repeated runs.
  ORIGINAL=""
  if [[ -d "$BACKUP_ROOT" ]]; then
    ORIGINAL="$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | head -1)"
  fi
  if [[ -z "$ORIGINAL" ]]; then
    warn "no backup found in ${BACKUP_ROOT/#$HOME/\~}"
  else
    info "using ${ORIGINAL/#$HOME/\~} (oldest = original)"
    if [[ ! -f "$ORIGINAL/.aerospace.toml" ]]; then
      skip "no .aerospace.toml in that backup"
    elif (( DRY_RUN )); then
      info "would restore ~/.aerospace.toml"
    else
      cp "$ORIGINAL/.aerospace.toml" "$AERO_CONF" && ok "restored ~/.aerospace.toml"
    fi
    for d in borders sketchybar; do
      [[ -d "$ORIGINAL/$d" ]] || continue
      if (( DRY_RUN )); then
        info "would restore ~/.config/$d"
      else
        mkdir -p "$HOME/.config"
        cp -R "$ORIGINAL/$d" "$HOME/.config/" && ok "restored ~/.config/$d"
      fi
    done
  fi
fi

# ===========================================================================
# 6. Backups
# ===========================================================================
step "Backups"
if (( PURGE_BACKUPS )); then
  if [[ ! -d "$BACKUP_ROOT" ]]; then
    skip "no backups to delete"
  elif (( DRY_RUN )); then
    info "would delete ${BACKUP_ROOT/#$HOME/\~}"
  else
    rm -rf "$BACKUP_ROOT"
    ok "deleted ${BACKUP_ROOT/#$HOME/\~}"
  fi
elif [[ -d "$BACKUP_ROOT" ]]; then
  count="$(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
  info "kept ${count} backup(s) in ${BACKUP_ROOT/#$HOME/\~}"
  info "remove them with: $(basename "$0") --purge-backups"
else
  skip "no backups present"
fi

# ===========================================================================
# 7. Summary
# ===========================================================================
cat <<SUMMARY

${C_B}${C_GRN}Uninstalled.${C_RST}

${C_DIM}Left alone on purpose:${C_RST}
  • Homebrew itself
  • your terminal (kitty, Ghostty, …) — hyprspace never installed it
  • AeroSpace's Accessibility grant, which macOS keeps until you remove it
    in System Settings ▸ Privacy & Security ▸ Accessibility
SUMMARY
(( DRY_RUN )) && printf '\n%s[dry run — nothing was actually changed]%s\n' "$C_YEL" "$C_RST"
printf '\n'
