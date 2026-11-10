#!/bin/bash
# Builds Inkdown and installs it into /Applications, replacing an older copy.
# Run from the project folder:  ./scripts/install.sh
set -e
cd "$(dirname "$0")/.."

echo "Building…"
xcodebuild -project Inkdown.xcodeproj -scheme Inkdown -configuration Release \
    -derivedDataPath build build > build-install.log 2>&1 || {
    echo "The build failed. See build-install.log."; exit 1; }
rm -f build-install.log

# Stop a running copy, then replace the installed app.
pkill -x Inkdown || true
sleep 1
rm -rf /Applications/Inkdown.app
cp -R build/Build/Products/Release/Inkdown.app /Applications/Inkdown.app

# Remove the built copies from the project folder. Otherwise Spotlight
# offers several apps called Inkdown, and it is easy to start the wrong one.
rm -rf build/Build/Products/Release/Inkdown.app build/Build/Products/Debug/Inkdown.app

# Tell macOS to re-read the list of Services, so "Convert to Markdown"
# shows up in Finder's right-click menu without logging out.
/System/Library/CoreServices/pbs -update

open /Applications/Inkdown.app
echo "Installed and started /Applications/Inkdown.app"
