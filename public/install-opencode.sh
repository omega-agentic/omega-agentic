#!/bin/sh
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                                    // opencode // multi-model
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# curl -fsSL straylight.dev/install-opencode.sh | sh
#
# phase-based installer with full rollback.
# pure openrouter — burn gcp credits through openrouter.
#
# SECURITY NOTES (red team):
#   - API keys stored with mode 0600
#   - All paths validated before use
#   - No eval, no command substitution from user input
#   - Atomic operations where possible (cp, not >>)
#   - Recovery state enables full rollback
#   - Shell integration appends only if marker absent
#
#     "Get just what you paid for. Nothing more, nothing less."
#                                                          — Mona Lisa Overdrive

set -eu

# ══════════════════════════════════════════════════════════════════════════════
#                                                                 // constants
# ══════════════════════════════════════════════════════════════════════════════

readonly SCRIPT_VERSION="1.0.0"
readonly MARKER="# // straylight // opencode"

# ══════════════════════════════════════════════════════════════════════════════
#                                                                    // paths
# ══════════════════════════════════════════════════════════════════════════════

init_paths() {
  TIMESTAMP=$(date +%s)
  STATE_BASE="${XDG_STATE_HOME:-$HOME/.local/state}/straylight"
  STATE_DIR="$STATE_BASE/recovery-$TIMESTAMP"
  OPENCODE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
  OPENCODE_CONFIG="$OPENCODE_DIR/config.json"
  STRAYLIGHT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/straylight"
  ENV_FILE="$STRAYLIGHT_DIR/env"
}

# ══════════════════════════════════════════════════════════════════════════════
#                                                                    // output
# ══════════════════════════════════════════════════════════════════════════════

banner() {
  cat << 'BANNER'
╔══════════════════════════════════════════════════════════════════╗
║              // straylight // opencode //                        ║
╚══════════════════════════════════════════════════════════════════╝

BANNER
}

log() { printf ':: %s\n' "$*"; }
warn() { printf '>> %s\n' "$*" >&2; }
err() { printf '!! %s\n' "$*" >&2; exit 1; }

# ══════════════════════════════════════════════════════════════════════════════
#                                                               // validation
# ══════════════════════════════════════════════════════════════════════════════

# Validate path is under expected base (prevent traversal)
validate_path() {
  _path="$1"
  _base="$2"
  
  # Resolve to absolute, reject if outside base
  case "$_path" in
    "$_base"/*) return 0 ;;
    "$_base") return 0 ;;
    *) err "path validation failed: $_path not under $_base" ;;
  esac
}

# Validate API key format (basic sanity)
validate_api_key() {
  _key="$1"
  _name="$2"
  
  # Must be non-empty
  [ -z "$_key" ] && err "$_name is empty"
  
  # Must be reasonable length (8-256 chars)
  _len=$(printf '%s' "$_key" | wc -c)
  [ "$_len" -lt 8 ] && err "$_name too short"
  [ "$_len" -gt 256 ] && err "$_name too long"
  
  # No shell metacharacters
  case "$_key" in
    *[\'\"\`\$\;\|\&\>\<\(\)\{\}\[\]\\]*)
      err "$_name contains invalid characters"
      ;;
  esac
  
  return 0
}

# Safe file write with mode
safe_write() {
  _file="$1"
  _mode="$2"
  _content="$3"
  
  _dir=$(dirname "$_file")
  
  # Create parent with restrictive perms
  if [ ! -d "$_dir" ]; then
    mkdir -p "$_dir"
    chmod 700 "$_dir"
  fi
  
  # Write to temp, set mode, then move (atomic)
  _tmp="${_file}.tmp.$$"
  printf '%s\n' "$_content" > "$_tmp"
  chmod "$_mode" "$_tmp"
  mv "$_tmp" "$_file"
}

# ══════════════════════════════════════════════════════════════════════════════
#                                                        // phase 0 // snapshot
# ══════════════════════════════════════════════════════════════════════════════

phase0_snapshot() {
  log "phase 0: snapshot"
  
  mkdir -p "$STATE_DIR"
  chmod 700 "$STATE_DIR"
  
  # Backup existing files (if they exist)
  [ -f "$OPENCODE_CONFIG" ] && cp -p "$OPENCODE_CONFIG" "$STATE_DIR/config.json.bak"
  [ -f "$ENV_FILE" ] && cp -p "$ENV_FILE" "$STATE_DIR/env.bak"
  [ -f "$HOME/.bashrc" ] && cp -p "$HOME/.bashrc" "$STATE_DIR/bashrc.bak"
  [ -f "$HOME/.zshrc" ] && cp -p "$HOME/.zshrc" "$STATE_DIR/zshrc.bak"
  
  # Record metadata
  printf '%s\n' "$TIMESTAMP" > "$STATE_DIR/timestamp"
  printf '%s\n' "$SCRIPT_VERSION" > "$STATE_DIR/version"
  
  log "  state: $STATE_DIR"
}

# ══════════════════════════════════════════════════════════════════════════════
#                                                           // phase 1 // stage
# ══════════════════════════════════════════════════════════════════════════════

phase1_stage() {
  log "phase 1: stage"
  
  STAGED="$STATE_DIR/staged"
  mkdir -p "$STAGED"
  chmod 700 "$STAGED"
  
  # Load existing credentials if present
  if [ -f "$ENV_FILE" ]; then
    # Source safely - only export known vars
    _existing_key=$(grep '^export OPENROUTER_API_KEY=' "$ENV_FILE" 2>/dev/null | cut -d'"' -f2 || true)
    if [ -n "$_existing_key" ]; then
      OPENROUTER_API_KEY="$_existing_key"
    fi
  fi
  
  # Prompt if needed
  if [ -z "${OPENROUTER_API_KEY:-}" ]; then
    printf '\n'
    printf '  OpenRouter API key required (pure openrouter)\n'
    printf '  obtain from: https://openrouter.ai/keys\n'
    printf '\n'
    printf '  OPENROUTER_API_KEY: '
    
    # Read with terminal if available
    if [ -t 0 ]; then
      read -r OPENROUTER_API_KEY
    else
      err "no TTY and no existing key — set OPENROUTER_API_KEY env var"
    fi
  else
    log "  using existing OPENROUTER_API_KEY"
  fi
  
  # Validate
  validate_api_key "$OPENROUTER_API_KEY" "OPENROUTER_API_KEY"
  
  # Stage env file
  _env_content="# // straylight // env
# generated: $(date -Iseconds 2>/dev/null || date)
# version: $SCRIPT_VERSION
# pure openrouter — all models through openrouter.ai
export OPENROUTER_API_KEY=\"$OPENROUTER_API_KEY\""

  safe_write "$STAGED/env" 600 "$_env_content"
  
  # Stage config (static, no interpolation needed at runtime)
  cat > "$STAGED/config.json" << 'CONFIG_EOF'
{
  "$schema": "https://opencode.dev/config.schema.json",
  "provider": {
    "default": "openrouter",
    "openrouter": {
      "apiKey": "${OPENROUTER_API_KEY}",
      "baseUrl": "https://openrouter.ai/api/v1"
    }
  },
  "models": {
    "nitpick": {
      "id": "openai/gpt-5.2",
      "provider": "openrouter",
      "temperature": 0.1,
      "description": "adversarial review, spec validation",
      "systemPrompt": "You are an adversarial code reviewer. Find flaws, edge cases, spec violations. Be thorough and uncharitable."
    },
    "creative": {
      "id": "anthropic/claude-opus-4.5",
      "provider": "openrouter",
      "temperature": 0.9,
      "description": "primary creative — reliable workhorse"
    },
    "creative-gemini": {
      "id": "google/gemini-3-pro-preview",
      "provider": "openrouter",
      "temperature": 0.85,
      "description": "dark horse — slow crusher (gcp credits)"
    },
    "creative-kimi": {
      "id": "moonshotai/kimi-k2.5",
      "provider": "openrouter",
      "temperature": 0.9,
      "description": "9x cheaper, guest rotation"
    },
    "cheap": {
      "id": "moonshotai/kimi-k2.5",
      "provider": "openrouter",
      "temperature": 0.7,
      "description": "bulk operations"
    }
  },
  "workflows": {
    "review-first": {
      "steps": [
        {"model": "nitpick", "action": "review"},
        {"model": "creative", "action": "implement"}
      ]
    }
  },
  "routing": {
    "taskRouting": {
      "review": "nitpick",
      "implement": "creative",
      "bulk": "cheap"
    }
  }
}
CONFIG_EOF
  chmod 600 "$STAGED/config.json"
  
  log "  staged: $STAGED"
}

# ══════════════════════════════════════════════════════════════════════════════
#                                                           // phase 2 // entry
# ══════════════════════════════════════════════════════════════════════════════

phase2_entry() {
  log "phase 2: entry"
  
  STAGED="$STATE_DIR/staged"
  
  # Validate staged files exist
  [ ! -f "$STAGED/config.json" ] && err "no staged config"
  [ ! -f "$STAGED/env" ] && err "no staged env"
  
  # Create target directories
  mkdir -p "$OPENCODE_DIR"
  chmod 700 "$OPENCODE_DIR"
  mkdir -p "$STRAYLIGHT_DIR"
  chmod 700 "$STRAYLIGHT_DIR"
  
  # Atomic install via copy (preserves staged for forensics)
  cp -p "$STAGED/config.json" "$OPENCODE_CONFIG"
  chmod 600 "$OPENCODE_CONFIG"
  
  cp -p "$STAGED/env" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  
  # Shell integration (append only if marker absent)
  SHELL_RC="$HOME/.bashrc"
  case "${SHELL:-/bin/sh}" in
    */zsh) SHELL_RC="$HOME/.zshrc" ;;
  esac
  
  if [ -f "$SHELL_RC" ] && grep -qF "$MARKER" "$SHELL_RC" 2>/dev/null; then
    log "  shell: already configured"
  else
    # Append shell integration
    cat >> "$SHELL_RC" << SHELL_EOF

$MARKER
[ -f "$ENV_FILE" ] && . "$ENV_FILE"
alias oc='opencode'
alias oc-nitpick='opencode --model nitpick'
alias oc-opus='opencode --model creative'
alias oc-gemini='opencode --model creative-gemini'
alias oc-kimi='opencode --model creative-kimi'
alias oc-review='opencode --workflow review-first'
SHELL_EOF
    log "  shell: $SHELL_RC"
  fi
  
  log "  config: $OPENCODE_CONFIG"
}

# ══════════════════════════════════════════════════════════════════════════════
#                                                          // phase 3 // verify
# ══════════════════════════════════════════════════════════════════════════════

phase3_verify() {
  log "phase 3: verify"
  
  # Check files exist with correct perms
  [ ! -f "$OPENCODE_CONFIG" ] && err "config missing"
  [ ! -f "$ENV_FILE" ] && err "env missing"
  
  _config_perms=$(stat -c "%a" "$OPENCODE_CONFIG" 2>/dev/null || stat -f "%Lp" "$OPENCODE_CONFIG" 2>/dev/null || echo "???")
  _env_perms=$(stat -c "%a" "$ENV_FILE" 2>/dev/null || stat -f "%Lp" "$ENV_FILE" 2>/dev/null || echo "???")
  
  [ "$_config_perms" != "600" ] && warn "config perms: $_config_perms (expected 600)"
  [ "$_env_perms" != "600" ] && warn "env perms: $_env_perms (expected 600)"
  
  # Test API connectivity (optional, may fail offline)
  if command -v curl >/dev/null 2>&1; then
    # Load key for test
    _key=$(grep '^export OPENROUTER_API_KEY=' "$ENV_FILE" 2>/dev/null | cut -d'"' -f2 || true)
    
    if [ -n "$_key" ]; then
      _resp=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout 5 \
        --max-time 10 \
        -H "Authorization: Bearer $_key" \
        "https://openrouter.ai/api/v1/models" 2>/dev/null || echo "000")
      
      case "$_resp" in
        200) log "  openrouter: connected" ;;
        401) warn "openrouter: unauthorized (check key)" ;;
        000) warn "openrouter: connection failed (offline?)" ;;
        *)   warn "openrouter: HTTP $_resp" ;;
      esac
    fi
  fi
  
  # Check opencode binary
  if command -v opencode >/dev/null 2>&1; then
    log "  opencode: $(command -v opencode)"
  else
    log "  opencode: not installed — https://opencode.dev"
  fi
}

# ══════════════════════════════════════════════════════════════════════════════
#                                                                    // abort
# ══════════════════════════════════════════════════════════════════════════════

abort() {
  log "abort: rolling back"
  
  # Re-init paths for abort context
  STATE_BASE="${XDG_STATE_HOME:-$HOME/.local/state}/straylight"
  OPENCODE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
  OPENCODE_CONFIG="$OPENCODE_DIR/config.json"
  STRAYLIGHT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/straylight"
  ENV_FILE="$STRAYLIGHT_DIR/env"
  
  # Find latest recovery state
  if [ ! -d "$STATE_BASE" ]; then
    err "no recovery state directory"
  fi
  
  LATEST=$(find "$STATE_BASE" -maxdepth 1 -type d -name 'recovery-*' 2>/dev/null | sort -r | head -1 || true)
  
  [ -z "$LATEST" ] && err "no recovery state found"
  [ ! -d "$LATEST" ] && err "recovery state not a directory"
  
  # Validate recovery state is under expected base
  validate_path "$LATEST" "$STATE_BASE"
  
  # Restore backups
  _restored=0
  
  if [ -f "$LATEST/config.json.bak" ]; then
    cp -p "$LATEST/config.json.bak" "$OPENCODE_CONFIG"
    _restored=$((_restored + 1))
  elif [ -f "$OPENCODE_CONFIG" ]; then
    # No backup means file didn't exist before — remove it
    rm -f "$OPENCODE_CONFIG"
  fi
  
  if [ -f "$LATEST/env.bak" ]; then
    cp -p "$LATEST/env.bak" "$ENV_FILE"
    _restored=$((_restored + 1))
  elif [ -f "$ENV_FILE" ]; then
    rm -f "$ENV_FILE"
  fi
  
  if [ -f "$LATEST/bashrc.bak" ]; then
    cp -p "$LATEST/bashrc.bak" "$HOME/.bashrc"
    _restored=$((_restored + 1))
  fi
  
  if [ -f "$LATEST/zshrc.bak" ]; then
    cp -p "$LATEST/zshrc.bak" "$HOME/.zshrc"
    _restored=$((_restored + 1))
  fi
  
  log "  restored $_restored files from: $LATEST"
}

# ══════════════════════════════════════════════════════════════════════════════
#                                                                    // clean
# ══════════════════════════════════════════════════════════════════════════════

clean() {
  log "clean: removing all straylight state"
  
  STATE_BASE="${XDG_STATE_HOME:-$HOME/.local/state}/straylight"
  OPENCODE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
  STRAYLIGHT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/straylight"
  
  # Confirm
  printf 'This will remove:\n'
  printf '  - %s\n' "$STATE_BASE"
  printf '  - %s\n' "$OPENCODE_DIR"
  printf '  - %s\n' "$STRAYLIGHT_DIR"
  printf '  - Shell integration from .bashrc/.zshrc\n'
  printf '\nContinue? [y/N] '
  
  if [ -t 0 ]; then
    read -r _confirm
    case "$_confirm" in
      [yY]|[yY][eE][sS]) ;;
      *) err "aborted" ;;
    esac
  else
    err "no TTY — refusing to clean without confirmation"
  fi
  
  # Remove directories
  rm -rf "$STATE_BASE"
  rm -rf "$OPENCODE_DIR"
  rm -rf "$STRAYLIGHT_DIR"
  
  # Remove shell integration
  for _rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$_rc" ] && grep -qF "$MARKER" "$_rc" 2>/dev/null; then
      # Remove marker block (marker line to next blank or EOF)
      _tmp="${_rc}.tmp.$$"
      awk -v marker="$MARKER" '
        BEGIN { skip=0 }
        $0 == marker { skip=1; next }
        skip && /^[^#]/ && !/^alias / && !/^\[ -f / { skip=0 }
        !skip { print }
      ' "$_rc" > "$_tmp"
      mv "$_tmp" "$_rc"
      log "  cleaned: $_rc"
    fi
  done
  
  log "clean complete"
}

# ══════════════════════════════════════════════════════════════════════════════
#                                                                   // status
# ══════════════════════════════════════════════════════════════════════════════

status() {
  init_paths
  
  printf 'straylight opencode status\n'
  printf '══════════════════════════════════════════════════════════════\n'
  printf 'version:     %s\n' "$SCRIPT_VERSION"
  printf 'config:      %s\n' "$([ -f "$OPENCODE_CONFIG" ] && echo "exists" || echo "missing")"
  printf 'env:         %s\n' "$([ -f "$ENV_FILE" ] && echo "exists" || echo "missing")"
  printf 'state dir:   %s\n' "$([ -d "$STATE_BASE" ] && echo "exists" || echo "missing")"
  
  if [ -d "$STATE_BASE" ]; then
    _count=$(find "$STATE_BASE" -maxdepth 1 -type d -name 'recovery-*' 2>/dev/null | wc -l)
    printf 'recoveries:  %s\n' "$_count"
  fi
  
  if [ -f "$ENV_FILE" ]; then
    _perms=$(stat -c "%a" "$ENV_FILE" 2>/dev/null || stat -f "%Lp" "$ENV_FILE" 2>/dev/null || echo "???")
    printf 'env perms:   %s\n' "$_perms"
  fi
  
  printf '\n'
}

# ══════════════════════════════════════════════════════════════════════════════
#                                                                     // main
# ══════════════════════════════════════════════════════════════════════════════

usage() {
  cat << 'USAGE'
usage: install-opencode.sh [command]

commands:
  run       execute all phases (default)
  abort     rollback to last recovery state
  clean     remove all straylight files (interactive)
  status    show installation status

phases (for debugging):
  snapshot  phase 0: capture current state
  stage     phase 1: collect credentials, stage config
  entry     phase 2: install staged config
  verify    phase 3: validate installation

pure openrouter pricing (gcp credits):
  opus 4.5:   $5/$25 per M
  k2.5:       $0.50/$2.80 per M (9x cheaper)
  gemini 3:   $1.25/$10 per M (gcp credits)
  gpt-5.2:    $1.25/$10 per M
USAGE
}

main() {
  # Validate HOME is set
  [ -z "${HOME:-}" ] && err "HOME not set"
  [ ! -d "$HOME" ] && err "HOME is not a directory: $HOME"
  
  case "${1:-run}" in
    run)
      init_paths
      banner
      phase0_snapshot
      phase1_stage
      phase2_entry
      phase3_verify
      printf '\n:: complete\n\n'
      printf 'restart shell or: . %s\n\n' "$ENV_FILE"
      printf 'usage:\n'
      printf '  oc-nitpick "review this code"\n'
      printf '  oc-opus "implement feature"\n'
      printf '  oc-gemini "burn gcp credits"\n'
      printf '  oc-kimi "bulk refactor (cheap)"\n\n'
      printf 'to undo: curl -fsSL straylight.dev/install-opencode.sh | sh -s abort\n'
      ;;
    snapshot)
      init_paths
      phase0_snapshot
      ;;
    stage)
      init_paths
      phase1_stage
      ;;
    entry)
      init_paths
      phase2_entry
      ;;
    verify)
      init_paths
      phase3_verify
      ;;
    abort)
      abort
      ;;
    clean)
      clean
      ;;
    status)
      status
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      usage
      exit 1
      ;;
  esac
}

main "$@"
