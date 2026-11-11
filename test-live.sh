#!/bin/sh
# Live test of the libtorrent bridge against Debian's official netinst torrent.
# Downloads a few MB, then pauses, resumes, and removes it with its data.
# Run ./build.sh first (it compiles build/TorrentBridge.o).
set -eu
cd "$(dirname "$0")"
LT=/opt/homebrew/opt/libtorrent-rasterbar
SSL=/opt/homebrew/opt/openssl@4
TMP="$PWD/build/smoke-tmp"
rm -rf "$TMP" && mkdir -p "$TMP"

if [ ! -f build/debian-netinst.torrent ]; then
  NAME=$(curl -s https://cdimage.debian.org/debian-cd/current/arm64/bt-cd/ |
         grep -o 'debian-[0-9.]*-arm64-netinst.iso.torrent' | head -1)
  curl -sS -o build/debian-netinst.torrent "https://cdimage.debian.org/debian-cd/current/arm64/bt-cd/$NAME"
fi

swiftc -O -target "$(uname -m)-apple-macos26.0" -import-objc-header Sources/Bridge/TorrentBridge.h \
  Tests/Bridge/main.swift build/TorrentBridge.o \
  -L$LT/lib -ltorrent-rasterbar -L$SSL/lib -lssl -lcrypto -lc++ -framework SystemConfiguration \
  -o build/bridge-smoke 2>/dev/null
./build/bridge-smoke build/debian-netinst.torrent "$TMP"
rm -rf "$TMP"
