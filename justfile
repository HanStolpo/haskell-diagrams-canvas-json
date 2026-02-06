# See flake.nix (just-flake)
import 'just-flake.just'

# Display the list of recipes
default:
    @just --list

# Run both Haskell and web dev servers (Ctrl+C to stop)
dev:
    #!/usr/bin/env bash
    set -e

    cleanup() {
        echo ""
        echo "Stopping servers..."
        kill $PID1 $PID2 2>/dev/null
        exit 0
    }
    trap cleanup INT TERM

    cabal run diagrams-canvas-json 2>&1 &
    PID1=$!
    npm run --prefix diagrams-canvas-json-web dev 2>&1 &
    PID2=$!

    echo "Dev servers starting..."
    echo "  Haskell: http://localhost:8080"
    echo "  Vite:    http://localhost:3000"
    echo "Press Ctrl+C to stop."
    echo ""

    wait
