#!/bin/sh
set -eu
cd "$(dirname "$0")"
mkdir -p .build/module-cache DNA.app/Contents/MacOS DNA.app/Contents/Resources
cp Assets/netsplit-servers.json DNA.app/Contents/Resources/netsplit-servers.json
cp Assets/DNA.icns DNA.app/Contents/Resources/DNA.icns
swiftc -O -module-cache-path .build/module-cache Sources/DNA/main.swift -o DNA.app/Contents/MacOS/DNA
codesign --force --sign - DNA.app
printf 'Built DNA.app. Launch with: open DNA.app\n'
