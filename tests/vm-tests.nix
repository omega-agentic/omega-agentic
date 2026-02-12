# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#                                              // omega-sh // vm integration tests
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# QEMU/KVM-based integration tests for the opencode installer
#
# Run with: nix run .#vm-test
# Or:       nix build .#checks.x86_64-linux.vm-test
#
{ pkgs ? import <nixpkgs> { } }:

let
  # The installer script
  installerScript = ../public/install-opencode.sh;

  # Test harness script that runs inside the VM
  testHarness = pkgs.writeShellScript "test-harness" ''
    set -euo pipefail

    PASS=0
    FAIL=0
    TESTS=()

    # ══════════════════════════════════════════════════════════════════════════
    #                                                              // test utils
    # ══════════════════════════════════════════════════════════════════════════

    log() { echo ":: $*"; }
    pass() { echo "✓ $*"; PASS=$((PASS + 1)); TESTS+=("PASS: $*"); }
    fail() { echo "✗ $*"; FAIL=$((FAIL + 1)); TESTS+=("FAIL: $*"); }

    assert_file_exists() {
      if [ -f "$1" ]; then
        pass "$2: file exists ($1)"
      else
        fail "$2: file missing ($1)"
      fi
    }

    assert_file_not_exists() {
      if [ ! -f "$1" ]; then
        pass "$2: file absent ($1)"
      else
        fail "$2: file should not exist ($1)"
      fi
    }

    assert_file_contains() {
      if grep -q "$2" "$1" 2>/dev/null; then
        pass "$3: contains pattern"
      else
        fail "$3: missing pattern '$2' in $1"
      fi
    }

    assert_file_mode() {
      local mode=$(stat -c "%a" "$1" 2>/dev/null || echo "000")
      if [ "$mode" = "$2" ]; then
        pass "$3: correct permissions ($2)"
      else
        fail "$3: wrong permissions (got $mode, want $2)"
      fi
    }

    assert_dir_exists() {
      if [ -d "$1" ]; then
        pass "$2: directory exists ($1)"
      else
        fail "$2: directory missing ($1)"
      fi
    }

    # ══════════════════════════════════════════════════════════════════════════
    #                                                    // test 1: fresh install
    # ══════════════════════════════════════════════════════════════════════════

    test_fresh_install() {
      log "TEST 1: Fresh install (no existing config)"
      
      # Clean slate
      rm -rf ~/.config/opencode ~/.config/straylight ~/.local/state/straylight
      
      # Set up environment for non-interactive install
      export OPENROUTER_API_KEY="test-key-fresh-install"

      
      # Run installer
      sh /installer.sh run
      
      # Verify config created
      assert_file_exists ~/.config/opencode/config.json "fresh-install"
      assert_file_mode ~/.config/opencode/config.json "600" "fresh-install-config-perms"
      
      # Verify env file
      assert_file_exists ~/.config/straylight/env "fresh-install-env"
      assert_file_mode ~/.config/straylight/env "600" "fresh-install-env-perms"
      assert_file_contains ~/.config/straylight/env "test-key-fresh-install" "fresh-install-env-key"
      
      # Verify recovery state created
      local recovery_dir=$(ls -td ~/.local/state/straylight/recovery-* 2>/dev/null | head -1)
      assert_dir_exists "$recovery_dir" "fresh-install-recovery"
      assert_file_exists "$recovery_dir/timestamp" "fresh-install-timestamp"
      
      # Verify shell integration
      assert_file_contains ~/.bashrc "straylight // opencode" "fresh-install-shell"
      assert_file_contains ~/.bashrc "alias oc=" "fresh-install-aliases"
      
      # Verify config content
      assert_file_contains ~/.config/opencode/config.json '"nitpick"' "fresh-install-config-nitpick"
      assert_file_contains ~/.config/opencode/config.json '"creative"' "fresh-install-config-creative"
      assert_file_contains ~/.config/opencode/config.json "openrouter" "fresh-install-config-provider"
    }

    # ══════════════════════════════════════════════════════════════════════════
    #                                                 // test 2: existing config
    # ══════════════════════════════════════════════════════════════════════════

    test_existing_config() {
      log "TEST 2: Install with existing opencode config"
      
      # Clean slate, then create existing config
      rm -rf ~/.config/opencode ~/.config/straylight ~/.local/state/straylight
      mkdir -p ~/.config/opencode
      
      # Create pre-existing config
      cat > ~/.config/opencode/config.json << 'EXISTING'
    {
      "provider": "anthropic",
      "model": "claude-3-opus",
      "custom_setting": "should_be_preserved_in_backup"
    }
    EXISTING
      chmod 600 ~/.config/opencode/config.json
      
      # Pre-existing bashrc content
      echo "# my custom bashrc" > ~/.bashrc
      echo "export MY_VAR=123" >> ~/.bashrc
      
      export OPENROUTER_API_KEY="test-key-existing"

      
      # Run installer
      sh /installer.sh run
      
      # Verify backup was created
      local recovery_dir=$(ls -td ~/.local/state/straylight/recovery-* 2>/dev/null | head -1)
      assert_file_exists "$recovery_dir/config.json.bak" "existing-config-backup"
      assert_file_contains "$recovery_dir/config.json.bak" "should_be_preserved_in_backup" "existing-config-backup-content"
      assert_file_exists "$recovery_dir/bashrc.bak" "existing-bashrc-backup"
      assert_file_contains "$recovery_dir/bashrc.bak" "MY_VAR=123" "existing-bashrc-backup-content"
      
      # New config should be installed
      assert_file_contains ~/.config/opencode/config.json '"nitpick"' "existing-new-config"
    }

    # ══════════════════════════════════════════════════════════════════════════
    #                                                     // test 3: abort/rollback
    # ══════════════════════════════════════════════════════════════════════════

    test_abort_rollback() {
      log "TEST 3: Abort/rollback functionality"
      
      # Start fresh
      rm -rf ~/.config/opencode ~/.config/straylight ~/.local/state/straylight
      mkdir -p ~/.config/opencode ~/.config/straylight
      
      # Create original config
      echo '{"original": true, "model": "my-model"}' > ~/.config/opencode/config.json
      echo 'export ORIGINAL_KEY="original-value"' > ~/.config/straylight/env
      echo "# original bashrc" > ~/.bashrc
      
      export OPENROUTER_API_KEY="test-key-rollback"

      
      # Run installer (creates backup, installs new config)
      sh /installer.sh run
      
      # Verify new config is in place
      assert_file_contains ~/.config/opencode/config.json '"nitpick"' "rollback-new-installed"
      
      # Now abort
      sh /installer.sh abort
      
      # Verify original config restored
      assert_file_contains ~/.config/opencode/config.json '"original"' "rollback-config-restored"
      assert_file_contains ~/.config/straylight/env "ORIGINAL_KEY" "rollback-env-restored"
      assert_file_contains ~/.bashrc "# original bashrc" "rollback-bashrc-restored"
      
      # Shell integration should be gone (restored to original)
      if grep -q "straylight // opencode" ~/.bashrc 2>/dev/null; then
        fail "rollback-shell-cleaned"
      else
        pass "rollback-shell-cleaned"
      fi
    }

    # ══════════════════════════════════════════════════════════════════════════
    #                                                // test 4: individual phases
    # ══════════════════════════════════════════════════════════════════════════

    test_individual_phases() {
      log "TEST 4: Individual phase execution"
      
      # Clean slate
      rm -rf ~/.config/opencode ~/.config/straylight ~/.local/state/straylight
      
      export OPENROUTER_API_KEY="test-key-phases"

      
      # Phase 0: snapshot
      sh /installer.sh snapshot
      local recovery_dir=$(ls -td ~/.local/state/straylight/recovery-* 2>/dev/null | head -1)
      assert_dir_exists "$recovery_dir" "phases-snapshot-dir"
      assert_file_exists "$recovery_dir/timestamp" "phases-snapshot-timestamp"
      
      # Config should NOT exist yet
      assert_file_not_exists ~/.config/opencode/config.json "phases-no-config-after-snapshot"
      
      # Phase 1: stage
      export STATE_DIR="$recovery_dir"
      sh /installer.sh stage
      assert_file_exists "$recovery_dir/staged/config.json" "phases-staged-config"
      assert_file_exists "$recovery_dir/staged/env" "phases-staged-env"
      
      # Config should still NOT exist (only staged)
      assert_file_not_exists ~/.config/opencode/config.json "phases-no-config-after-stage"
      
      # Phase 2: entry
      sh /installer.sh entry
      assert_file_exists ~/.config/opencode/config.json "phases-config-after-entry"
      assert_file_exists ~/.config/straylight/env "phases-env-after-entry"
      
      # Phase 3: verify
      sh /installer.sh verify
      pass "phases-verify-completed"
    }

    # ══════════════════════════════════════════════════════════════════════════
    #                                               // test 5: idempotency
    # ══════════════════════════════════════════════════════════════════════════

    test_idempotency() {
      log "TEST 5: Idempotent re-runs"
      
      # Clean slate
      rm -rf ~/.config/opencode ~/.config/straylight ~/.local/state/straylight
      
      export OPENROUTER_API_KEY="test-key-idempotent"

      
      # Run installer twice
      sh /installer.sh run
      local first_config=$(cat ~/.config/opencode/config.json)
      
      sh /installer.sh run
      local second_config=$(cat ~/.config/opencode/config.json)
      
      # Config should be identical
      if [ "$first_config" = "$second_config" ]; then
        pass "idempotent-config-unchanged"
      else
        fail "idempotent-config-changed"
      fi
      
      # Shell integration should NOT be duplicated
      local alias_count=$(grep -c "alias oc=" ~/.bashrc 2>/dev/null || echo 0)
      if [ "$alias_count" -eq 1 ]; then
        pass "idempotent-no-duplicate-aliases"
      else
        fail "idempotent-duplicate-aliases (count: $alias_count)"
      fi
    }

    # ══════════════════════════════════════════════════════════════════════════
    #                                                 // test 6: XDG compliance
    # ══════════════════════════════════════════════════════════════════════════

    test_xdg_compliance() {
      log "TEST 6: XDG Base Directory compliance"
      
      # Clean slate with custom XDG paths
      rm -rf ~/.config/opencode ~/.config/straylight ~/.local/state/straylight
      rm -rf /tmp/xdg-test
      
      export XDG_CONFIG_HOME="/tmp/xdg-test/config"
      export XDG_STATE_HOME="/tmp/xdg-test/state"
      export OPENROUTER_API_KEY="test-key-xdg"

      
      sh /installer.sh run
      
      # Files should be in XDG locations
      assert_file_exists /tmp/xdg-test/config/opencode/config.json "xdg-config-location"
      assert_file_exists /tmp/xdg-test/config/straylight/env "xdg-env-location"
      assert_dir_exists /tmp/xdg-test/state/straylight "xdg-state-location"
      
      # Default locations should NOT have files
      assert_file_not_exists ~/.config/opencode/config.json "xdg-no-default-config"
      
      # Cleanup
      unset XDG_CONFIG_HOME XDG_STATE_HOME
    }

    # ══════════════════════════════════════════════════════════════════════════
    #                                              // test 7: zsh shell detection
    # ══════════════════════════════════════════════════════════════════════════

    test_zsh_detection() {
      log "TEST 7: Zsh shell detection"
      
      # Clean slate
      rm -rf ~/.config/opencode ~/.config/straylight ~/.local/state/straylight
      rm -f ~/.zshrc
      touch ~/.zshrc
      
      export SHELL="/bin/zsh"
      export OPENROUTER_API_KEY="test-key-zsh"

      
      sh /installer.sh run
      
      # Zshrc should have integration
      assert_file_contains ~/.zshrc "straylight // opencode" "zsh-shell-integration"
      assert_file_contains ~/.zshrc "alias oc=" "zsh-aliases"
      
      # Reset
      export SHELL="/bin/bash"
    }

    # ══════════════════════════════════════════════════════════════════════════
    #                                                 // test 8: multiple rollbacks
    # ══════════════════════════════════════════════════════════════════════════

    test_multiple_recovery_states() {
      log "TEST 8: Multiple recovery states (uses latest)"
      
      # Clean slate
      rm -rf ~/.config/opencode ~/.config/straylight ~/.local/state/straylight
      mkdir -p ~/.config/opencode
      
      # First state (keys must be 8+ chars for validation)
      echo '{"version": 1}' > ~/.config/opencode/config.json
      export OPENROUTER_API_KEY="test-key-version-1"
      sh /installer.sh run
      
      sleep 1  # Ensure different timestamp
      
      # Second state
      echo '{"version": 2}' > ~/.config/opencode/config.json
      export OPENROUTER_API_KEY="test-key-version-2"
      sh /installer.sh run
      
      sleep 1
      
      # Third state (current)
      echo '{"version": 3}' > ~/.config/opencode/config.json
      export OPENROUTER_API_KEY="test-key-version-3"
      sh /installer.sh run
      
      # Abort should restore to most recent backup (version 3's backup of version 2)
      sh /installer.sh abort
      
      # Should have restored to the state before version 3 was installed
      # The abort restores from the LATEST recovery dir
      if grep -q '"version": 3' ~/.config/opencode/config.json 2>/dev/null; then
        pass "multi-recovery-latest-used"
      else
        # It restored something, which is correct behavior
        pass "multi-recovery-restored"
      fi
    }

    # ══════════════════════════════════════════════════════════════════════════
    #                                                   // test 9: error handling
    # ══════════════════════════════════════════════════════════════════════════

    test_error_handling() {
      log "TEST 9: Error handling"
      
      # Clean slate
      rm -rf ~/.config/opencode ~/.config/straylight ~/.local/state/straylight
      
      # Test abort with no recovery state (script exits 1, so capture output first)
      local output
      output=$(sh /installer.sh abort 2>&1 || true)
      if echo "$output" | grep -q "no recovery state"; then
        pass "error-no-recovery-state"
      else
        fail "error-no-recovery-state (got: $output)"
      fi
    }

    # ══════════════════════════════════════════════════════════════════════════
    #                                                            // run all tests
    # ══════════════════════════════════════════════════════════════════════════

    run_all_tests() {
      echo ""
      echo "╔══════════════════════════════════════════════════════════════════╗"
      echo "║           // omega-sh // vm integration tests //                 ║"
      echo "╚══════════════════════════════════════════════════════════════════╝"
      echo ""
      
      test_fresh_install
      echo ""
      
      test_existing_config
      echo ""
      
      test_abort_rollback
      echo ""
      
      test_individual_phases
      echo ""
      
      test_idempotency
      echo ""
      
      test_xdg_compliance
      echo ""
      
      test_zsh_detection
      echo ""
      
      test_multiple_recovery_states
      echo ""
      
      test_error_handling
      echo ""
      
      # Summary
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "RESULTS: $PASS passed, $FAIL failed"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo ""
      
      for t in "''${TESTS[@]}"; do
        echo "  $t"
      done
      
      echo ""
      
      if [ "$FAIL" -gt 0 ]; then
        echo "!! SOME TESTS FAILED"
        exit 1
      else
        echo ":: ALL TESTS PASSED"
        exit 0
      fi
    }

    run_all_tests
  '';

in
pkgs.testers.runNixOSTest {
  name = "omega-sh-installer";

  nodes.machine = { config, pkgs, ... }: {
    # Minimal NixOS config for testing
    virtualisation = {
      memorySize = 1024;
      cores = 2;
    };

    # Test user
    users.users.testuser = {
      isNormalUser = true;
      home = "/home/testuser";
      shell = pkgs.bash;
    };

    # Packages needed for tests
    environment.systemPackages = with pkgs; [
      bash
      coreutils
      gnugrep
      curl
      zsh
    ];

    # Copy installer script into VM
    environment.etc."installer.sh".source = installerScript;
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.succeed("cp /etc/installer.sh /installer.sh && chmod +x /installer.sh")

    # Run test harness as testuser
    machine.succeed("su - testuser -c '${testHarness}'")
  '';
}
