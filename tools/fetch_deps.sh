#!/usr/bin/env bash
# Downloads the git-ignored addons at pinned versions. Used by CI, and works
# locally from Git Bash too: run it from anywhere, it installs into the project
# root. Existing folders are left untouched, so delete one to force a re-download.
set -euo pipefail

TUBE_URL="https://github.com/jonandrewdavis/tube/archive/0370fa40dd4988b0bff8ebee15225761c327208d.zip"
GUT_URL="https://github.com/bitwes/Gut/archive/refs/tags/v9.7.1.zip"
# WebRTC for native builds (Android, Windows); browsers have it built in.
WEBRTC_URL="https://github.com/godotengine/webrtc-native/releases/download/1.2.2-stable/godot-extension-webrtc_native.zip"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# fetch <url> <name>: downloads and extracts into $TMP/<name>
fetch() {
    echo "Downloading $2..."
    # CURL_EXTRA: optional extra flags, e.g. --ssl-revoke-best-effort on Windows
    # networks where the certificate revocation check is blocked.
    curl -fsSL ${CURL_EXTRA:-} "$1" -o "$TMP/$2.zip"
    unzip -q "$TMP/$2.zip" -d "$TMP/$2"
}

# Addon archives nest their folder at different depths, so find it by name.
install_addon() {
    local url="$1" name="$2"
    [ -d "$ROOT/addons/$name" ] && return
    fetch "$url" "$name"
    local src
    src="$(find "$TMP/$name" -type d -path "*/addons/$name" | head -n 1)"
    [ -n "$src" ] || { echo "addons/$name not found in $url" >&2; exit 1; }
    mkdir -p "$ROOT/addons"
    mv "$src" "$ROOT/addons/$name"
}

install_addon "$TUBE_URL" tube
install_addon "$GUT_URL" gut
install_addon "$WEBRTC_URL" webrtc_native

echo "Dependencies ready."
