#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
destination="$HOME/Applications/Corrector.app"
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# Build outside the repo so Spotlight and launchers such as Raycast only ever see the installed copy.
build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT
./build.sh "$build_dir/Corrector.app"

if pgrep -qf "$destination/Contents/MacOS/Corrector"; then
    osascript -e 'tell application id "com.emile.corrector" to quit'
    while pgrep -qf "$destination/Contents/MacOS/Corrector"; do sleep 0.2; done
fi
rm -rf "$destination"
mkdir -p "$HOME/Applications"
ditto "$build_dir/Corrector.app" "$destination"
"$lsregister" -f "$destination"
mdimport "$destination" 2>/dev/null || true
echo "Installed $destination"
