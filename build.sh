#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
app_path="${1:-dist/Corrector.app}"
mkdir -p "$app_path/Contents/MacOS"
cp Info.plist "$app_path/Contents/Info.plist"
swiftc -O -framework AppKit -framework Security Sources/Corrector/*.swift -o "$app_path/Contents/MacOS/Corrector"
echo "Built $app_path"
