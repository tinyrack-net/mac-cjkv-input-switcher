#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}/.."
OUTPUT="${1:-$ROOT/dist/MacCJKVInputSwitcher.app}"
ARM=$(find "$ROOT/dist/arm64" -type f -path "*/Contents/MacOS/MacCJKVInputSwitcher" -print -quit 2>/dev/null || true)
INTEL=$(find "$ROOT/dist/x86_64" -type f -path "*/Contents/MacOS/MacCJKVInputSwitcher" -print -quit 2>/dev/null || true)
if [[ -z "$ARM" || -z "$INTEL" ]]; then
  echo "Both arm64 and x86_64 apps are required" >&2
  find "$ROOT/dist" -maxdepth 6 -type f -print >&2
  exit 1
fi
chmod +x "$ARM" "$INTEL"
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
