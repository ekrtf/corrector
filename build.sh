#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
app_path="${1:-dist/Corrector.app}"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp Info.plist "$app_path/Contents/Info.plist"
cp Resources/AppIcon.icns "$app_path/Contents/Resources/AppIcon.icns"
swiftc -O -framework AppKit Sources/Corrector/*.swift -o "$app_path/Contents/MacOS/Corrector"
echo "Built $app_path"
