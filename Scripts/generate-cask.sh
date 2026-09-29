#!/bin/zsh
set -euo pipefail
VERSION="${1:?version required}"
SHA256="${2:?sha256 required}"
OUTPUT="${3:-dist/mac-cjkv-input-switcher.rb}"
cat > "$OUTPUT" <<EOF
cask "mac-cjkv-input-switcher" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/tinyrack-net/mac-cjkv-input-switcher/releases/download/v$VERSION/MacCJKVInputSwitcher-$VERSION.dmg"
  name "Mac CJKV Input Switcher"
  desc "Menu bar input source switcher for macOS"
  homepage "https://github.com/tinyrack-net/mac-cjkv-input-switcher"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :ventura
  app "MacCJKVInputSwitcher.app"
  zap trash: [
    "~/Library/LaunchAgents/com.winetree.MacCJKVInputSwitcher.plist",
    "~/Library/Logs/MacCJKVInputSwitcher.log",
    "~/Library/Preferences/com.winetree.MacCJKVInputSwitcher.plist",
  ]
end
EOF
printf "%s\n" "$OUTPUT"
