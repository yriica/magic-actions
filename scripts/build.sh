#!/bin/bash
# Build (and optionally test) MagicActions.
#   ./scripts/build.sh        # build Debug app
#   ./scripts/build.sh test   # run unit tests
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate --quiet

if [[ "${1:-build}" == "test" ]]; then
  xcodebuild -project MagicActions.xcodeproj -scheme MagicActions \
    -configuration Debug -derivedDataPath build/DerivedData \
    -destination "platform=macOS" test
else
  xcodebuild -project MagicActions.xcodeproj -scheme MagicActions \
    -configuration Debug -derivedDataPath build/DerivedData build
  echo "built: $(pwd)/build/DerivedData/Build/Products/Debug/MagicActions.app"
fi
