#!/usr/bin/env bash
# =============================================================================
# OpenClaw / Clawdbot Uninstaller — macOS
# Usage: bash uninstall-macos.sh [--keep-config]
#   --keep-config   Skip deleting ~/.openclaw and ~/.clawdbot (keep your data)
# =============================================================================

set -euo pipefail

KEEP_CONFIG=false
for arg in "$@"; do
  [[ "$arg" == "--keep-config" ]] && KEEP_CONFIG=true
done

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

# ── Step 1: Stop & remove LaunchAgents ───────────────────────────────────────
info "Step 1/5  Stopping LaunchAgent daemons..."
PLISTS=(
  "$HOME/Library/LaunchAgents/com.openclaw.gateway.plist"
  "$HOME/Library/LaunchAgents/com.clawdbot.gateway.plist"
  "$HOME/Library/LaunchAgents/com.moltbot.gateway.plist"
)
found_any=false
for plist in "${PLISTS[@]}"; do
  if [ -f "$plist" ]; then
    found_any=true
    launchctl unload "$plist" 2>/dev/null && success "Unloaded: $(basename "$plist")" || warn "Could not unload (may already be stopped): $(basename "$plist")"
    rm -f "$plist" && success "Removed:  $plist"
  fi
done
$found_any || info "No LaunchAgent plists found — skipping."

# ── Step 2: Kill remaining processes ─────────────────────────────────────────
info "Step 2/5  Killing any remaining gateway processes..."
killed=false
for pattern in "openclaw.*gateway" "clawdbot.*gateway" "openclaw-gateway"; do
  if pgrep -f "$pattern" &>/dev/null; then
    pkill -f "$pattern" 2>/dev/null && success "Killed process matching: $pattern"
    killed=true
  fi
done
$killed || info "No running gateway processes found."

# ── Step 3: Uninstall npm packages ───────────────────────────────────────────
info "Step 3/5  Uninstalling npm global packages..."
for pkg in openclaw clawdbot moltbot; do
  if npm list -g --depth=0 2>/dev/null | grep -q "$pkg"; then
    npm uninstall -g "$pkg" 2>/dev/null && success "Uninstalled npm package: $pkg"
  else
    info "npm package not found: $pkg — skipping."
  fi
done

# ── Step 4: Remove config directories ────────────────────────────────────────
if [ "$KEEP_CONFIG" = true ]; then
  warn "Step 4/5  --keep-config set, skipping config directory removal."
else
  info "Step 4/5  Backing up and removing config directories..."
  BACKUP_DATE=$(date +%Y%m%d_%H%M%S)
  for dir in "$HOME/.openclaw" "$HOME/.clawdbot" "$HOME/.moltbot"; do
    if [ -d "$dir" ]; then
      backup="${dir}-backup-${BACKUP_DATE}"
      cp -r "$dir" "$backup" && success "Backed up: $dir → $backup"
      rm -rf "$dir"          && success "Removed:   $dir"
    fi
  done
fi

# ── Step 5: Remove system crontab entries (if any) ───────────────────────────
info "Step 5/5  Checking system crontab for openclaw/clawdbot entries..."
if crontab -l 2>/dev/null | grep -qiE "openclaw|clawd"; then
  warn "Found crontab entries — removing them..."
  crontab -l 2>/dev/null | grep -viE "openclaw|clawd" | crontab -
  success "Crontab entries removed."
else
  info "No crontab entries found — skipping."
fi

# ── Verification ─────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}========================================${NC}"
echo -e "${BOLD}  Verification                          ${NC}"
echo -e "${BOLD}========================================${NC}"

all_ok=true

npm list -g --depth=0 2>/dev/null | grep -qiE "openclaw|clawd|moltbot" \
  && { error "npm packages still present"; all_ok=false; } \
  || success "npm packages removed"

for dir in "$HOME/.openclaw" "$HOME/.clawdbot" "$HOME/.moltbot"; do
  [ -d "$dir" ] \
    && { error "Config dir still exists: $dir"; all_ok=false; } \
    || success "Config dir removed: $dir"
done

for plist in "$HOME/Library/LaunchAgents/com.openclaw.gateway.plist" \
             "$HOME/Library/LaunchAgents/com.clawdbot.gateway.plist"; do
  [ -f "$plist" ] \
    && { error "LaunchAgent still present: $plist"; all_ok=false; } \
    || success "LaunchAgent removed: $(basename "$plist")"
done

pgrep -f "openclaw.*gateway\|clawdbot.*gateway" &>/dev/null \
  && { error "Gateway process still running"; all_ok=false; } \
  || success "No gateway processes running"

echo ""
if $all_ok; then
  echo -e "${GREEN}${BOLD}✅  OpenClaw fully removed from this machine.${NC}"
else
  echo -e "${RED}${BOLD}⚠️   Some items could not be removed — see errors above.${NC}"
  exit 1
fi
