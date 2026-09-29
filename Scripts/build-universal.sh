#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}/.."
OUTPUT="${1:-$ROOT/dist/MacCJKVInputSwitcher.app}"
ARM="$ROOT/dist/arm64/MacCJKVInputSwitcher.app/Contents/MacOS/MacCJKVInputSwitcher"
INTEL="$ROOT/dist/x86_64/MacCJKVInputSwitcher.app/Contents/MacOS/MacCJKVInputSwitcher"
[[ -x "$ARM" && -x "$INTEL" ]] || { echo "Both arm64 and x86_64 apps are required" >&2; exit 1; }
python3 - "$OUTPUT" "$ROOT/Info.plist" <<'PY2'
import os, shutil, sys
out, plist = sys.argv[1:]
shutil.rmtree(out, ignore_errors=True)
os.makedirs(os.path.join(out, "Contents", "MacOS"))
os.makedirs(os.path.join(out, "Contents", "Resources"))
shutil.copy2(plist, os.path.join(out, "Contents", "Info.plist"))
PY2
lipo -create "$ARM" "$INTEL" -output "$OUTPUT/Contents/MacOS/MacCJKVInputSwitcher"
chmod 755 "$OUTPUT/Contents/MacOS/MacCJKVInputSwitcher"
echo "$OUTPUT"
