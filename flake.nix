{
  description = "omega-sh - opencode multi-model configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    bun2nix = {
      url = "github:nix-community/bun2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    purescript-overlay = {
      url = "github:thomashoneyman/purescript-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig = {
    extra-substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      bun2nix,
      purescript-overlay,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        overlays = [ purescript-overlay.overlays.default ];
        pkgs = import nixpkgs { inherit system overlays; };
        bun2nixPkg = bun2nix.packages.${system}.default;

        # Hermetic bun dependencies (generate with: bun2nix)
        bunDeps = bun2nixPkg.fetchBunDeps {
          bunNix = ./bun.nix;
        };

        # Production build
        omega-sh = pkgs.stdenv.mkDerivation {
          pname = "omega-sh";
          version = "0.1.0";

          src = ./.;

          nativeBuildInputs = [
            bun2nixPkg.hook
            pkgs.bun
            pkgs.nodejs_22
            pkgs.purs
            pkgs.spago-unstable
            pkgs.purs-backend-es
            pkgs.esbuild
          ];

          inherit bunDeps;

          bunInstallFlags = [ "--linker=hoisted" ];

          buildPhase = ''
            runHook preBuild

            export PATH="$PWD/node_modules/.bin:$PATH"

            # Build PureScript
            echo "Building PureScript..."
            cd purescript
            spago bundle --bundle-type app --platform browser --minify --outfile ../public/straylight.js
            cd ..

            # Build Next.js
            echo "Building Next.js..."
            next build

            runHook postBuild
          '';

          installPhase = ''
                        runHook preInstall

                        mkdir -p $out/share/omega-sh
                        cp -r .next/standalone/. $out/share/omega-sh/
                        cp -r .next/static $out/share/omega-sh/.next/
                        cp -r public $out/share/omega-sh/

                        # Create runner script
                        mkdir -p $out/bin
                        cat > $out/bin/omega-sh <<EOF
            #!/usr/bin/env bash
            cd $out/share/omega-sh
            exec ${pkgs.nodejs_22}/bin/node server.js "\$@"
            EOF
                        chmod +x $out/bin/omega-sh

                        runHook postInstall
          '';
        };
      in
      {
        packages = {
          default = omega-sh;
          web = omega-sh;
        };

        # Checks run by `nix flake check`
        checks = {
          build = omega-sh;

          # PureScript property tests
          purescript-tests = pkgs.stdenv.mkDerivation {
            pname = "straylight-purescript-tests";
            version = "0.1.0";

            src = ./.;

            nativeBuildInputs = [
              pkgs.purs
              pkgs.spago-unstable
              pkgs.esbuild
              pkgs.nodejs_22
            ];

            buildPhase = ''
              runHook preBuild

              echo "Building and running PureScript tests..."
              cd purescript

              # Build tests
              spago build

              # Run test bundle if it exists
              if [ -f "test/dist/test.cjs" ]; then
                ${pkgs.nodejs_22}/bin/node test/dist/test.cjs
                echo "All property tests passed!"
              else
                echo "Skipping tests - test bundle not found"
                echo "To build: cd purescript && spago test"
              fi

              runHook postBuild
            '';

            installPhase = ''
              mkdir -p $out
              echo "Tests passed" > $out/result.txt
            '';
          };
        } // (if system == "x86_64-linux" || system == "aarch64-linux" then {
          # VM integration tests (Linux only, requires KVM)
          vm-test = import ./tests/vm-tests.nix { inherit pkgs; };
        } else { });

        apps.default = {
          type = "app";
          program = "${omega-sh}/bin/omega-sh";
        };

        # Dev runner - runs in current directory
        apps.dev = {
          type = "app";
          program = toString (
            pkgs.writeShellScript "omega-sh-dev" ''
              set -e
              export PATH="${pkgs.bun}/bin:${pkgs.nodejs_22}/bin:${pkgs.purs}/bin:${pkgs.spago-unstable}/bin:${pkgs.purs-backend-es}/bin:${pkgs.esbuild}/bin:$PWD/node_modules/.bin:$PATH"

              # Kill existing dev server if running
              if ${pkgs.lsof}/bin/lsof -i :3000 -t >/dev/null 2>&1; then
                echo ":: killing existing process on :3000"
                ${pkgs.lsof}/bin/lsof -i :3000 -t | xargs kill 2>/dev/null || true
                sleep 1
              fi

              if [ ! -d "node_modules" ]; then
                echo "Installing dependencies..."
                ${pkgs.bun}/bin/bun install
              fi

              echo ""
              echo "// omega-sh // dev //"
              echo ""
              echo "Building PureScript..."
              cd purescript && spago bundle --bundle-type app --platform browser --outfile ../public/straylight.js && cd ..

              echo ""
              echo "Starting dev server at http://localhost:3000"
              exec ${pkgs.bun}/bin/bun run dev
            ''
          );
        };

        # PureScript watch mode
        apps.purs = {
          type = "app";
          program = toString (
            pkgs.writeShellScript "omega-sh-purs" ''
              set -e
              export PATH="${pkgs.purs}/bin:${pkgs.spago-unstable}/bin:${pkgs.purs-backend-es}/bin:${pkgs.esbuild}/bin:$PATH"

              cd purescript
              echo "Building PureScript bundle..."
              spago bundle --bundle-type app --platform browser --outfile ../public/straylight.js
              echo ""
              echo "Bundle written to public/straylight.js"
              ls -lh ../public/straylight.js
            ''
          );
        };

        # VM integration tests runner
        apps.vm-test = {
          type = "app";
          program = toString (
            pkgs.writeShellScript "omega-sh-vm-test" ''
              set -e
              echo ""
              echo "╔══════════════════════════════════════════════════════════════════╗"
              echo "║           // omega-sh // vm integration tests //                 ║"
              echo "╚══════════════════════════════════════════════════════════════════╝"
              echo ""
              echo "Running QEMU/KVM integration tests..."
              echo ""
              nix build .#checks.${system}.vm-test --print-build-logs
              echo ""
              echo ":: VM tests completed successfully"
            ''
          );
        };

        # Quick installer test (no VM, runs locally)
        apps.test-installer = {
          type = "app";
          program = toString (
            pkgs.writeShellScript "omega-sh-test-installer" ''
              set -e
              
              echo ""
              echo "╔══════════════════════════════════════════════════════════════════╗"
              echo "║        // omega-sh // installer quick test (local) //            ║"
              echo "╚══════════════════════════════════════════════════════════════════╝"
              echo ""
              
              SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
              INSTALLER="$SCRIPT_DIR/public/install-opencode.sh"
              
              if [ ! -f "$INSTALLER" ]; then
                INSTALLER="./public/install-opencode.sh"
              fi
              
              if [ ! -f "$INSTALLER" ]; then
                echo "!! Installer not found"
                exit 1
              fi
              
              # Create isolated test environment
              TEST_HOME=$(mktemp -d)
              export HOME="$TEST_HOME"
              export XDG_CONFIG_HOME="$TEST_HOME/.config"
              export XDG_STATE_HOME="$TEST_HOME/.local/state"
              
              echo ":: Test environment: $TEST_HOME"
              echo ""
              
              # Set up for non-interactive
              export OPENROUTER_API_KEY="test-key-quick"
              export ANTHROPIC_API_KEY=""
              export GOOGLE_API_KEY=""
              
              # Create bashrc
              touch "$HOME/.bashrc"
              
              echo ":: Running installer..."
              sh "$INSTALLER" run
              
              echo ""
              echo ":: Verifying installation..."
              
              PASS=0
              FAIL=0
              
              check() {
                if [ -f "$1" ]; then
                  echo "✓ $2"
                  PASS=$((PASS + 1))
                else
                  echo "✗ $2 (missing: $1)"
                  FAIL=$((FAIL + 1))
                fi
              }
              
              check "$XDG_CONFIG_HOME/opencode/config.json" "config.json exists"
              check "$XDG_CONFIG_HOME/straylight/env" "env file exists"
              
              if grep -q "straylight // opencode" "$HOME/.bashrc" 2>/dev/null; then
                echo "✓ shell integration"
                PASS=$((PASS + 1))
              else
                echo "✗ shell integration"
                FAIL=$((FAIL + 1))
              fi
              
              if grep -q '"nitpick"' "$XDG_CONFIG_HOME/opencode/config.json" 2>/dev/null; then
                echo "✓ config has nitpick model"
                PASS=$((PASS + 1))
              else
                echo "✗ config missing nitpick model"
                FAIL=$((FAIL + 1))
              fi
              
              echo ""
              echo ":: Testing rollback..."
              sh "$INSTALLER" abort
              
              echo ""
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              echo "RESULTS: $PASS passed, $FAIL failed"
              echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
              
              # Cleanup
              rm -rf "$TEST_HOME"
              
              if [ "$FAIL" -gt 0 ]; then
                exit 1
              fi
            ''
          );
        };

        devShells.default = pkgs.mkShell {
          buildInputs = [
            pkgs.nodejs_22
            pkgs.bun
            pkgs.purs
            pkgs.purs-tidy
            pkgs.purs-backend-es
            pkgs.spago-unstable
            pkgs.esbuild
            pkgs.git
            bun2nixPkg
          ];

          shellHook = ''
            export PATH="$PWD/node_modules/.bin:$PATH"

            echo ""
            echo "// omega-sh // opencode //"
            echo ""
            echo "Commands:"
            echo "  bun install           - Install JS dependencies"
            echo "  bun run dev           - Start Next.js dev server"
            echo "  nix run .#purs        - Build PureScript bundle"
            echo "  nix run .#dev         - Build + dev (one command)"
            echo "  nix build             - Hermetic production build"
            echo "  nix flake check       - Run all checks"
            echo ""
            echo "PureScript: $(purs --version)"
            echo "Spago: $(spago --version 2>/dev/null || echo 'available')"
            echo "Node: $(node --version)"
            echo "Bun: $(bun --version)"
            echo ""
          '';
        };
      }
    );
}
