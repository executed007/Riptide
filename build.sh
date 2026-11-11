#!/bin/sh
# Builds build/Riptide.app: runs search tests, compiles the libtorrent bridge and
# the SwiftUI app, bundles libtorrent + OpenSSL into the app, and signs it.
# Requires: Xcode Command Line Tools, Homebrew libtorrent-rasterbar and dylibbundler.
set -eu
cd "$(dirname "$0")"

LT=/opt/homebrew/opt/libtorrent-rasterbar
SSL=/opt/homebrew/opt/openssl@4
BOOST=/opt/homebrew/opt/boost
ARCH="$(uname -m)"
TARGET="$ARCH-apple-macos26.0"
APP="build/Riptide.app"

# Must match the flags libtorrent was built with (lib/pkgconfig/libtorrent-rasterbar.pc).
LT_CFLAGS="-fexceptions -I$LT/include -I$BOOST/include -I$SSL/include \
  -DTORRENT_LINKING_SHARED -DBOOST_ASIO_NO_DEPRECATED -DBOOST_SYSTEM_USE_UTF8 \
  -DTORRENT_ABI_VERSION=2 -DTORRENT_USE_OPENSSL -DTORRENT_USE_LIBCRYPTO -DTORRENT_SSL_PEERS \
  -DOPENSSL_NO_SSL2 -DOPENSSL_NO_SSL3 -DOPENSSL_NO_TLS1 -DOPENSSL_NO_TLS1_1 -DOPENSSL_NO_DTLS1"
LT_LIBS="-L$LT/lib -ltorrent-rasterbar -L$SSL/lib -lssl -lcrypto -lc++"

mkdir -p build

echo "== Search tests"
swiftc -O -target "$TARGET" Sources/App/Search.swift Tests/Search/main.swift -o build/search-tests
./build/search-tests

echo "== Compiling libtorrent bridge"
clang++ -std=c++17 -fobjc-arc -O2 -target "$TARGET" $LT_CFLAGS \
  -c Sources/Bridge/TorrentBridge.mm -o build/TorrentBridge.o

echo "== Compiling app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp Resources/Info.plist "$APP/Contents/Info.plist"
swiftc -O -parse-as-library -target "$TARGET" \
  -import-objc-header Sources/Bridge/TorrentBridge.h \
  Sources/App/*.swift build/TorrentBridge.o $LT_LIBS \
  -framework SystemConfiguration -framework CoreFoundation \
  -o "$APP/Contents/MacOS/Riptide"

echo "== Bundling libraries"
dylibbundler -of -b -x "$APP/Contents/MacOS/Riptide" -d "$APP/Contents/Frameworks" \
  -p @executable_path/../Frameworks/ >/dev/null

echo "== Signing"
codesign --force --deep --sign - "$APP"
echo "Built $APP"
