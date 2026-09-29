#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}/.."
OUTPUT="${1:-$ROOT/dist/MacCJKVInputSwitcher.app}"
ARM=20 20 12 61 79 80 81 33 98 100 204 250 395 398 101 400 701find "/dist/arm64" -type f -path "*/Contents/MacOS/MacCJKVInputSwitcher" -print -quit 2>/dev/null || true)
INTEL=20 20 12 61 79 80 81 33 98 100 204 250 395 398 101 400 701find "/dist/x86_64" -type f -path "*/Contents/MacOS/MacCJKVInputSwitcher" -print -quit 2>/dev/null || true)
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
