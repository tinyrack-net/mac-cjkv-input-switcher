#!/bin/zsh
set -euo pipefail
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
BUMP=$1
[[ -z "$(git status --porcelain)" ]] || exit 1
[[ $(git branch --show-current) == main ]] || exit 1
git fetch origin main
[[ $(git rev-parse HEAD) == $(git rev-parse origin/main) ]] || exit 1
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
IFS=. read -r MAJOR MINOR PATCH <<< "$VERSION"
case "$BUMP" in
 major) MAJOR=$((MAJOR+1)); MINOR=0; PATCH=0 ;;
 minor) MINOR=$((MINOR+1)); PATCH=0 ;;
 patch) PATCH=$((PATCH+1)) ;;
 *) exit 64 ;;
esac
NEXT="$MAJOR.$MINOR.$PATCH"
git switch -c "release/v$NEXT"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEXT" Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((MAJOR*10000+MINOR*100+PATCH))" Info.plist
git add Info.plist
git commit -m "release: v$NEXT"
git push -u origin "release/v$NEXT"
printf 'Create a PR from release/v%s into main.
' "$NEXT"
