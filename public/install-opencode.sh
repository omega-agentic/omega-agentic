#!/bin/sh
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                                    // opencode // multi-model
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# curl -fsSL straylight.dev/install-opencode.sh | sh
#
# phase-based installer with full rollback.
# pure openrouter — burn gcp credits through openrouter.
#
#     "Get just what you paid for. Nothing more, nothing less."
#                                                          — Mona Lisa Overdrive

set -e

TIMESTAMP=$(date +%s)
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/straylight/recovery-$TIMESTAMP"
OPENCODE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
OPENCODE_CONFIG="$OPENCODE_DIR/config.json"
ENV_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/straylight/env"

# ══════════════════════════════════════════════════════════════════════════════
#                                                                    // output
# ══════════════════════════════════════════════════════════════════════════════

banner() {
  echo "╔══════════════════════════════════════════════════════════════════╗"
  echo "║              // straylight // opencode //                        ║"
  echo "╚══════════════════════════════════════════════════════════════════╝"
  echo ""
}

log() { echo ":: $*"; }
err() { echo "!! $*" >&2; exit 1; }

# ══════════════════════════════════════════════════════════════════════════════
#                                                        // phase 0 // snapshot
# ══════════════════════════════════════════════════════════════════════════════

phase0_snapshot() {
  log "phase 0: snapshot"
  mkdir -p "$STATE_DIR"
  
  [ -f "$OPENCODE_CONFIG" ] && cp "$OPENCODE_CONFIG" "$STATE_DIR/config.json.bak"
  [ -f "$ENV_FILE" ] && cp "$ENV_FILE" "$STATE_DIR/env.bak"
  [ -f "$HOME/.bashrc" ] && cp "$HOME/.bashrc" "$STATE_DIR/bashrc.bak"
  [ -f "$HOME/.zshrc" ] && cp "$HOME/.zshrc" "$STATE_DIR/zshrc.bak"
  
  echo "$TIMESTAMP" > "$STATE_DIR/timestamp"
  log "  state saved: $STATE_DIR"
}

# ══════════════════════════════════════════════════════════════════════════════
#                                                           // phase 1 // stage
# ══════════════════════════════════════════════════════════════════════════════

phase1_stage() {
  log "phase 1: stage"
  
  STAGED="$STATE_DIR/staged"
  mkdir -p "$STAGED"
  
  # credentials — check existing env
  [ -f "$ENV_FILE" ] && . "$ENV_FILE"
  
  if [ -z "$OPENROUTER_API_KEY" ]; then
    echo ""
    echo "  OpenRouter API key required (pure openrouter, gcp credits)"
    echo "  obtain from: https://openrouter.ai/keys"
    echo ""
    printf "  OPENROUTER_API_KEY: "
    read -r OPENROUTER_API_KEY
    [ -z "$OPENROUTER_API_KEY" ] && err "openrouter key required"
  else
    log "  using existing OPENROUTER_API_KEY"
  fi
  
  # write env — openrouter only
  cat > "$STAGED/env" << EOF
# // straylight // env
# generated: $(date -Iseconds)
# pure openrouter — all models through openrouter.ai
export OPENROUTER_API_KEY="${OPENROUTER_API_KEY}"
EOF
  
  # write config — pure openrouter
  cat > "$STAGED/config.json" << 'EOF'
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
EOF

  log "  staged: $STAGED"
}

# ══════════════════════════════════════════════════════════════════════════════
#                                                           // phase 2 // entry
# ══════════════════════════════════════════════════════════════════════════════

phase2_entry() {
  log "phase 2: entry"
  
  STAGED="$STATE_DIR/staged"
  [ ! -f "$STAGED/config.json" ] && err "no staged config"
  
  mkdir -p "$OPENCODE_DIR"
  mkdir -p "$(dirname "$ENV_FILE")"
  
  cp "$STAGED/config.json" "$OPENCODE_CONFIG"
  chmod 600 "$OPENCODE_CONFIG"
  
  cp "$STAGED/env" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  
  # shell integration
  SHELL_RC="$HOME/.bashrc"
  case "$SHELL" in
    */zsh) SHELL_RC="$HOME/.zshrc" ;;
  esac
  
  if ! grep -q "straylight // opencode" "$SHELL_RC" 2>/dev/null; then
    cat >> "$SHELL_RC" << EOF

# // straylight // opencode
[ -f "$ENV_FILE" ] && . "$ENV_FILE"
alias oc='opencode'
alias oc-nitpick='opencode --model nitpick'
alias oc-opus='opencode --model creative'
alias oc-gemini='opencode --model creative-gemini'
alias oc-kimi='opencode --model creative-kimi'
alias oc-review='opencode --workflow review-first'
EOF
    log "  shell: $SHELL_RC"
  fi
  
  log "  activated: $OPENCODE_CONFIG"
}

# ══════════════════════════════════════════════════════════════════════════════
#                                                          // phase 3 // verify
# ══════════════════════════════════════════════════════════════════════════════

phase3_verify() {
  log "phase 3: verify"
  
  [ -f "$OPENCODE_CONFIG" ] || err "config missing"
  [ -f "$ENV_FILE" ] || err "env missing"
  
  . "$ENV_FILE"
  
  if command -v curl >/dev/null 2>&1 && [ -n "$OPENROUTER_API_KEY" ]; then
    RESP=$(curl -s -o /dev/null -w "%{http_code}" \
      -H "Authorization: Bearer $OPENROUTER_API_KEY" \
      "https://openrouter.ai/api/v1/models" 2>/dev/null || echo "000")
    
    if [ "$RESP" = "200" ]; then
      log "  openrouter: connected"
    else
      log "  openrouter: HTTP $RESP (check key)"
    fi
  fi
  
  if command -v opencode >/dev/null 2>&1; then
    log "  opencode: $(which opencode)"
  else
    log "  opencode: not found — install from https://opencode.dev"
  fi
}

# ══════════════════════════════════════════════════════════════════════════════
#                                                                    // abort
# ══════════════════════════════════════════════════════════════════════════════

abort() {
  log "abort: rolling back"
  
  STATE_BASE="${XDG_STATE_HOME:-$HOME/.local/state}/straylight"
  
  if [ ! -d "$STATE_BASE" ]; then
    err "no recovery state"
  fi
  
  LATEST=$(ls -td "$STATE_BASE"/recovery-* 2>/dev/null | head -1 || true)
  
  [ -z "$LATEST" ] && err "no recovery state"
  
  [ -f "$LATEST/config.json.bak" ] && cp "$LATEST/config.json.bak" "$OPENCODE_CONFIG"
  [ -f "$LATEST/env.bak" ] && cp "$LATEST/env.bak" "$ENV_FILE"
  [ -f "$LATEST/bashrc.bak" ] && cp "$LATEST/bashrc.bak" "$HOME/.bashrc"
  [ -f "$LATEST/zshrc.bak" ] && cp "$LATEST/zshrc.bak" "$HOME/.zshrc"
  
  log "  restored from: $LATEST"
}

# ══════════════════════════════════════════════════════════════════════════════
#                                                                     // main
# ══════════════════════════════════════════════════════════════════════════════

usage() {
  echo "usage: $0 {run|snapshot|stage|entry|verify|abort}"
  echo ""
  echo "  run       execute all phases"
  echo "  abort     full rollback"
  echo ""
  echo "pure openrouter pricing (gcp credits):"
  echo "  opus 4.5:   \$5/\$25 per M"
  echo "  k2.5:       \$0.50/\$2.80 per M (9x cheaper)"
  echo "  gemini 3:   \$1.25/\$10 per M (gcp credits)"
  echo "  gpt-5.2:    \$1.25/\$10 per M"
}

main() {
  case "${1:-run}" in
    snapshot) phase0_snapshot ;;
    stage)    phase1_stage ;;
    entry)    phase2_entry ;;
    verify)   phase3_verify ;;
    abort)    abort ;;
    run)
      banner
      phase0_snapshot
      phase1_stage
      phase2_entry
      phase3_verify
      echo ""
      echo ":: complete"
      echo ""
      echo "restart shell or: . $ENV_FILE"
      echo ""
      echo "usage:"
      echo "  oc-nitpick 'review this code'"
      echo "  oc-opus 'implement feature'"
      echo "  oc-gemini 'burn gcp credits'"
      echo "  oc-kimi 'bulk refactor (cheap)'"
      echo ""
      echo "to undo: curl -fsSL straylight.dev/install-opencode.sh | sh -s abort"
      ;;
    *)
      usage
      ;;
  esac
}

main "$@"
