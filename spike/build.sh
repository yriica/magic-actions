#!/bin/bash
# Build the M0 spike tool.
set -euo pipefail
cd "$(dirname "$0")"
clang -fobjc-arc -fmodules \
  -F /System/Library/PrivateFrameworks \
  -framework MultitouchSupport \
  -framework Cocoa \
  -o mtdump mtdump.m
echo "built: $(pwd)/mtdump"
