#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PBX="$ROOT/MagicActions.xcodeproj/project.pbxproj"
python3 - "$PBX" <<'PY'
from pathlib import Path
import re, sys
p = Path(sys.argv[1])
text = p.read_text()
text2, n = re.subn(
    r"(AppIcon\.icon \*/ = \{isa = PBXFileReference; lastKnownFileType = )folder(; name = AppIcon\.icon;)",
    r"\1folder.iconcomposer.icon\2",
    text,
)
if n:
    p.write_text(text2)
print(f"fixed AppIcon.icon file type ({n})")
PY
