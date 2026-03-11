#!/usr/bin/env bash
# =============================================================================
# OpenClaw / Clawdbot Uninstaller — macOS
# Usage: bash uninstall-macos.sh [--keep-config | --purge]
#   --keep-config   Skip deleting config dirs (keep your data)
#   --purge         Delete config dirs immediately, no backup
# =============================================================================

set -euo pipefail

KEEP_CONFIG=false
PURGE=false
for arg in "$@"; do
  [[ "$arg" == "--keep-config" ]] && KEEP_CONFIG=true
  [[ "$arg" == "--purge" ]]       && PURGE=true
done

if $KEEP_CONFIG && $PURGE; then
  echo "Error: --keep-config and --purge are mutually exclusive."
  exit 1
fi

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${BOLD}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERR]${NC}   $*"; }

echo ""
echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}  OpenClaw Uninstaller — macOS          ${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""

# ── Step 1: Stop & remove ALL LaunchAgent plists ─────────────────────────────
# Covers: gateway + node daemon, default + legacy labels, multi-profile variants
# Sources: constants.js
#   GATEWAY: com.clawdbot.gateway  (default)
#            com.clawdbot.<profile> (multi-profile)
#            com.steipete.clawdbot.gateway (legacy)
#   NODE:    com.clawdbot.node
#   openclaw variants: com.openclaw.gateway, com.openclaw.node
#   moltbot: com.moltbot.gateway
info "Step 1/5  Stopping LaunchAgent daemons..."

unload_plist() {
  local plist="$1"
  if [ -f "$plist" ]; then
    launchctl bootout "gui/$(id -u)" "$plist" 2>/dev/null \
      || launchctl unload "$plist" 2>/dev/null \
      || true
    rm -f "$plist" && success "Removed:  $plist"
  fi
}

# Fixed known labels
for label in \
  "com.clawdbot.gateway" \
  "com.clawdbot.node" \
  "com.steipete.clawdbot.gateway" \
  "com.openclaw.gateway" \
  "com.openclaw.node" \
  "com.moltbot.gateway"; do
  unload_plist "$HOME/Library/LaunchAgents/${label}.plist"
done

# Wildcard sweep — catches multi-profile variants like com.clawdbot.<profile>
shopt -s nullglob
for plist in \
  "$HOME/Library/LaunchAgents/com.clawdbot."*.plist \
  "$HOME/Library/LaunchAgents/com.openclaw."*.plist \
  "$HOME/Library/LaunchAgents/com.moltbot."*.plist; do
  unload_plist "$plist"
done
shopt -u nullglob

# ── Step 2: Kill remaining processes ─────────────────────────────────────────
info "Step 2/5  Killing any remaining processes..."
killed=false
for pattern in \
  "openclaw.*gateway" "clawdbot.*gateway" "openclaw-gateway" \
  "openclaw.*node"    "clawdbot.*node"    \
  "openclaw/dist/entry" "clawdbot/dist/entry"; do
  if pgrep -f "$pattern" &>/dev/null; then
    pkill -f "$pattern" 2>/dev/null && success "Killed: $pattern"
    killed=true
  fi
done
$killed || info "No running processes found."

# ── Step 3: Uninstall npm packages ───────────────────────────────────────────
info "Step 3/5  Uninstalling npm global packages..."
for pkg in openclaw clawdbot moltbot; do
  if npm list -g --depth=0 2>/dev/null | grep -q "$pkg"; then
    npm uninstall -g "$pkg" 2>/dev/null && success "Uninstalled: $pkg"
  else
    info "Not found: $pkg — skipping."
  fi
done

# ── Step 4: Remove config / state directories ─────────────────────────────────
# Default: ~/.clawdbot  (CLAWDBOT_STATE_DIR overrides this)
# Also check ~/.openclaw and ~/.moltbot
STATE_DIR="${CLAWDBOT_STATE_DIR:-}"
DIRS_TO_REMOVE=("$HOME/.openclaw" "$HOME/.clawdbot" "$HOME/.moltbot")
# If user has a custom CLAWDBOT_STATE_DIR, add it too
if [ -n "$STATE_DIR" ] && [ "$STATE_DIR" != "$HOME/.clawdbot" ]; then
  DIRS_TO_REMOVE+=("$STATE_DIR")
fi

if [ "$KEEP_CONFIG" = true ]; then
  warn "Step 4/5  --keep-config set, skipping config directory removal."
elif [ "$PURGE" = true ]; then
  warn "Step 4/5  --purge: deleting config directories WITHOUT backup..."
  for dir in "${DIRS_TO_REMOVE[@]}"; do
    if [ -d "$dir" ]; then
      rm -rf "$dir" && success "Purged: $dir"
    fi
  done
else
  info "Step 4/5  Backing up and removing config directories..."
  BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
  for dir in "${DIRS_TO_REMOVE[@]}"; do
    if [ -d "$dir" ]; then
      backup="${dir}-backup-${BACKUP_DATE}"
      cp -r "$dir" "$backup" && success "Backed up: $dir → $backup"
      rm -rf "$dir"          && success "Removed:   $dir"
    fi
  done
fi

# ── Step 5: Clean up crontab + tmp logs ──────────────────────────────────────
info "Step 5/5  Cleaning up crontab and temp files..."

# System crontab entries
if crontab -l 2>/dev/null | grep -qiE "openclaw|clawd"; then
  crontab -l 2>/dev/null | grep -viE "openclaw|clawd" | crontab -
  success "Crontab entries removed."
else
  info "No crontab entries found."
fi

# /tmp log files written by the gateway (e.g. /tmp/clawdbot-YYYY-MM-DD.log)
shopt -s nullglob
for f in /tmp/clawdbot*.log /tmp/openclaw*.log /tmp/clawdbot /tmp/openclaw; do
  rm -rf "$f" && success "Removed tmp: $f"
done
shopt -u nullglob

# ── Verification ─────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}  Verification                          ${NC}"
echo -e "${BOLD}========================================${NC}"

all_ok=true

# npm packages
npm list -g --depth=0 2>/dev/null | grep -qiE "openclaw|clawd|moltbot" \
  && { error "npm packages still present"; all_ok=false; } \
  || success "npm packages removed"

# Config dirs
for dir in "$HOME/.openclaw" "$HOME/.clawdbot" "$HOME/.moltbot"; do
  [ -d "$dir" ] \
    && { error "Config dir still exists: $dir"; all_ok=false; } \
    || success "Config dir removed: $dir"
done

# LaunchAgents (wildcard)
remaining_plists=()
shopt -s nullglob
for plist in \
  "$HOME/Library/LaunchAgents/com.clawdbot."*.plist \
  "$HOME/Library/LaunchAgents/com.openclaw."*.plist \
  "$HOME/Library/LaunchAgents/com.moltbot."*.plist \
  "$HOME/Library/LaunchAgents/com.steipete.clawdbot."*.plist; do
  remaining_plists+=("$plist")
done
shopt -u nullglob
if [ ${#remaining_plists[@]} -gt 0 ]; then
  for p in "${remaining_plists[@]}"; do error "LaunchAgent still present: $p"; done
  all_ok=false
else
  success "All LaunchAgents removed"
fi

# Processes
if pgrep -f "openclaw|clawdbot" | grep -qv "grep\|uninstall" 2>/dev/null; then
  error "openclaw/clawdbot processes still running"
  all_ok=false
else
  success "No processes running"
fi

echo ""
if $all_ok; then
  echo -e "${GREEN}${BOLD}✅  OpenClaw fully removed from this machine.${NC}"
else
  echo -e "${RED}${BOLD}⚠️   Some items could not be removed — see errors above.${NC}"
  exit 1
fi
