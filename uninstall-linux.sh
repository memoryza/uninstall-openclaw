#!/usr/bin/env bash
# =============================================================================
# OpenClaw / Clawdbot Uninstaller — Linux / WSL2
# Usage: bash uninstall-linux.sh [--keep-config | --purge]
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
echo -e "${BOLD}  OpenClaw Uninstaller — Linux          ${NC}"
echo -e "${BOLD}========================================${NC}"
echo ""

# ── Step 1: Stop & remove ALL systemd user units ──────────────────────────────
# Covers: gateway + node daemon for clawdbot and openclaw
# Sources: constants.js
#   GATEWAY: clawdbot-gateway  (default)
#            clawdbot-gateway-<profile> (multi-profile)
#   NODE:    clawdbot-node
#   openclaw variants: openclaw-gateway, openclaw-node
info "Step 1/5  Stopping systemd user units..."

stop_unit() {
  local unit="$1"
  if systemctl --user list-unit-files 2>/dev/null | grep -q "^${unit}"; then
    systemctl --user stop    "$unit" 2>/dev/null && success "Stopped:  $unit"
    systemctl --user disable "$unit" 2>/dev/null && success "Disabled: $unit"
    local svc="$HOME/.config/systemd/user/${unit}.service"
    [ -f "$svc" ] && rm -f "$svc" && success "Removed:  $svc"
    return 0
  fi
  # Also try removing the service file even if not listed (may be stale)
  local svc="$HOME/.config/systemd/user/${unit}.service"
  if [ -f "$svc" ]; then
    rm -f "$svc" && success "Removed stale unit file: $svc"
  fi
}

SYSTEMD_AVAILABLE=false
systemctl --user status &>/dev/null && SYSTEMD_AVAILABLE=true || true

if $SYSTEMD_AVAILABLE; then
  for unit in \
    "clawdbot-gateway" \
    "clawdbot-node" \
    "openclaw-gateway" \
    "openclaw-node" \
    "moltbot-gateway"; do
    stop_unit "$unit"
  done

  # Multi-profile variants: clawdbot-gateway-<profile>
  for svc_file in "$HOME/.config/systemd/user/clawdbot-gateway-"*.service \
                  "$HOME/.config/systemd/user/openclaw-gateway-"*.service 2>/dev/null; do
    [ -f "$svc_file" ] || continue
    unit=$(basename "$svc_file" .service)
    stop_unit "$unit"
  done

  systemctl --user daemon-reload 2>/dev/null || true
else
  info "systemd not available (WSL2 without systemd?) — skipping unit removal."
  # Still clean up stale service files
  for f in \
    "$HOME/.config/systemd/user/clawdbot-gateway.service" \
    "$HOME/.config/systemd/user/clawdbot-node.service" \
    "$HOME/.config/systemd/user/openclaw-gateway.service" \
    "$HOME/.config/systemd/user/openclaw-node.service"; do
    [ -f "$f" ] && rm -f "$f" && success "Removed stale: $f"
  done
fi

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
STATE_DIR="${CLAWDBOT_STATE_DIR:-}"
DIRS_TO_REMOVE=("$HOME/.openclaw" "$HOME/.clawdbot" "$HOME/.moltbot")
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

if crontab -l 2>/dev/null | grep -qiE "openclaw|clawd"; then
  crontab -l 2>/dev/null | grep -viE "openclaw|clawd" | crontab -
  success "Crontab entries removed."
else
  info "No crontab entries found."
fi

# /tmp log files
for f in /tmp/clawdbot*.log /tmp/openclaw*.log /tmp/clawdbot /tmp/openclaw; do
  [ -e "$f" ] && rm -rf "$f" && success "Removed tmp: $f"
done

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

if $SYSTEMD_AVAILABLE; then
  for unit in clawdbot-gateway clawdbot-node openclaw-gateway openclaw-node; do
    systemctl --user is-active "$unit" 2>/dev/null | grep -q "^active" \
      && { error "systemd unit still active: $unit"; all_ok=false; } \
      || success "systemd unit not active: $unit"
  done
fi

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
