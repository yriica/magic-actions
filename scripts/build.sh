#!/bin/bash
# Build (and optionally test/install) MagicActions.
#   ./scripts/build.sh          # build Debug app
#   ./scripts/build.sh test     # run unit tests
#   ./scripts/build.sh install  # build, then replace /Applications/MagicActions.app and relaunch
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet

case "${1:-build}" in
  test)
    xcodebuild -project MagicActions.xcodeproj -scheme MagicActions \
      -configuration Debug -derivedDataPath build/DerivedData \
      -destination "platform=macOS" test
    ;;
  install)
    xcodebuild -project MagicActions.xcodeproj -scheme MagicActions \
      -configuration Debug -derivedDataPath build/DerivedData build
    pkill -x MagicActions || true
    sleep 1
    rm -rf /Applications/MagicActions.app
    ditto build/DerivedData/Build/Products/Debug/MagicActions.app /Applications/MagicActions.app
    # Remove the build product so Spotlight/Launchpad does not list a duplicate app.
    rm -rf build/DerivedData/Build/Products/Debug/MagicActions.app
    open /Applications/MagicActions.app
    echo "installed: /Applications/MagicActions.app"
    echo "note: ad-hoc signed rebuilds may require re-granting Accessibility / Input Monitoring."
    ;;
  *)
    xcodebuild -project MagicActions.xcodeproj -scheme MagicActions \
      -configuration Debug -derivedDataPath build/DerivedData build
    echo "built: $(pwd)/build/DerivedData/Build/Products/Debug/MagicActions.app"
    ;;
esac
