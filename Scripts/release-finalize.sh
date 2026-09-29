#!/bin/zsh
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
[[ -z "$(git status --porcelain)" ]] || exit 1
[[ $(git branch --show-current) == main ]] || exit 1
git pull --ff-only
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
git tag -s "v$VERSION" -m "Release v$VERSION"
git push origin "v$VERSION"
