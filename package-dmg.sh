#!/bin/sh
set -eu
cd "$(dirname "$0")"
./build.sh
mkdir -p dist
stage=$(mktemp -d "$PWD/.build/dmg-stage.XXXXXX")
ditto DNA.app "$stage/DNA.app"
ln -s /Applications "$stage/Applications"
printf 'Drag DNA into Applications. Quit the previous running version before opening DNA.\nRequires macOS 13 or later. Locally signed development build; not notarized.\n' > "$stage/Install.txt"
hdiutil create -volname DNA -srcfolder "$stage" -ov -format UDZO dist/DNA-1.3.dmg
hdiutil verify dist/DNA-1.3.dmg
codesign --verify --deep --strict DNA.app
