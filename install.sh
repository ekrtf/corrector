#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
./build.sh
destination="$HOME/Applications/Corrector.app"
mkdir -p "$HOME/Applications"
ditto dist/Corrector.app "$destination"
mdimport "$destination" 2>/dev/null || true
echo "Installed $destination"
