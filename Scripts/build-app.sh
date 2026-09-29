#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}/.."
INPUT="${1:?input executable required}"
OUTPUT="${2:?output app required}"
[[ -x "$INPUT" ]] || { echo "Missing executable: $INPUT" >&2; exit 1; }
python3 - "$OUTPUT" "$INPUT" "$ROOT/Info.plist" <<'PY'
import os, shutil, sys
out, binary, plist = sys.argv[1:]
shutil.rmtree(out, ignore_errors=True)
os.makedirs(os.path.join(out, 'Contents', 'MacOS'))
os.makedirs(os.path.join(out, 'Contents', 'Resources'))
shutil.copy2(binary, os.path.join(out, 'Contents', 'MacOS', 'MacCJKVInputSwitcher'))
shutil.copy2(plist, os.path.join(out, 'Contents', 'Info.plist'))
os.chmod(os.path.join(out, 'Contents', 'MacOS', 'MacCJKVInputSwitcher'), 0o755)
PY
echo "$OUTPUT"
