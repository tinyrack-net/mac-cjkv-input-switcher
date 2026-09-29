#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h}/.."
APP="${1:?app bundle required}"
VERSION="${2:?version required}"
OUTPUT="${3:-$ROOT/dist/MacCJKVInputSwitcher-${VERSION}.dmg}"
STAGING="$ROOT/dist/.dmg-staging"
[[ -d "$APP" ]] || { echo "Missing app bundle: $APP" >&2; exit 1; }
python3 - "$STAGING" "$APP" <<'PY'
import os, shutil, sys
staging, app = sys.argv[1:]
shutil.rmtree(staging, ignore_errors=True)
os.makedirs(staging)
shutil.copytree(app, os.path.join(staging, os.path.basename(app)))
os.symlink('/Applications', os.path.join(staging, 'Applications'))
PY
rm -f "$OUTPUT"
/usr/bin/hdiutil create -volname "Mac CJKV Input Switcher" -srcfolder "$STAGING" -ov -format UDZO "$OUTPUT" >/dev/null
python3 - "$STAGING" <<'PY'
import shutil, sys
shutil.rmtree(sys.argv[1], ignore_errors=True)
PY
echo "$OUTPUT"
