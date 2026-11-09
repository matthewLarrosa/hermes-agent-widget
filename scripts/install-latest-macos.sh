#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA="$ROOT/.build-dev-macos"
INSTALL_DIR="$HOME/Applications"
INSTALL_APP="$INSTALL_DIR/Hermes Widget Dev.app"
INSTALLED_EXTENSION="$INSTALL_APP/Contents/PlugIns/HermesMacWidget.appex"
WIDGET_BUNDLE_ID="com.mlarrosa.HermesAgentWidget.macOS.WidgetV3"
BUILD_NUMBER="$(date -u +%Y%m%d%H%M%S)"
SHARED_DESTINATION_DIR="$HOME/Library/Application Support/HermesAgentWidget"
SHARED_DESTINATION_FILE="$SHARED_DESTINATION_DIR/destinations.v1.json"
SHARED_INSTALLATION_FILE="$SHARED_DESTINATION_DIR/installation.v1.json"

cd "$ROOT"
command -v xcodegen >/dev/null || {
    printf 'error: xcodegen is required\n' >&2
    exit 1
}

printf 'Building clean Hermes widget (%s)\n' "$BUILD_NUMBER"
xcodegen generate
rm -rf "$DERIVED_DATA"

xcodebuild \
    -quiet \
    -project HermesAgentWidget.xcodeproj \
    -scheme HermesMac \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    CODE_SIGNING_ALLOWED=NO \
    clean build

BUILT_APP="$DERIVED_DATA/Build/Products/Debug/HermesMac.app"
BUILT_EXTENSION="$BUILT_APP/Contents/PlugIns/HermesMacWidget.appex"
test -x "$BUILT_APP/Contents/MacOS/HermesMac"
test -x "$BUILT_EXTENSION/Contents/MacOS/HermesMacWidget"

ACTUAL_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$BUILT_EXTENSION/Contents/Info.plist")"
ACTUAL_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUILT_EXTENSION/Contents/Info.plist")"
if [[ "$ACTUAL_BUILD" != "$BUILD_NUMBER" ]]; then
    printf 'error: expected extension build %s, got %s\n' "$BUILD_NUMBER" "$ACTUAL_BUILD" >&2
    exit 1
fi

pkill -x HermesMac 2>/dev/null || true
pkill -x HermesMacWidget 2>/dev/null || true
pkill -x WidgetConfigurationExtension 2>/dev/null || true
killall linkd 2>/dev/null || true
killall siriappintentsd 2>/dev/null || true

rm -rf "$INSTALL_APP"
mkdir -p "$INSTALL_DIR"
/usr/bin/ditto "$BUILT_APP" "$INSTALL_APP"

# CODE_SIGNING_ALLOWED=NO leaves only linker signatures. PlugInKit rejects that
# widget as unsandboxed because its entitlements are not bound to the bundle.
codesign --force --sign - --timestamp=none \
    --entitlements "$ROOT/Config/HermesMacWidget.entitlements" \
    "$INSTALLED_EXTENSION"
codesign --force --sign - --timestamp=none \
    --entitlements "$ROOT/Config/HermesMac.entitlements" \
    "$INSTALL_APP"
codesign --verify --deep --strict "$INSTALL_APP"

# Migrate data saved by older ad-hoc builds. macOS can detach App Group
# UserDefaults from cfprefsd for ad-hoc App Intent processes, so current builds
# use a narrowly sandboxed shared file instead.
if [[ ! -f "$SHARED_DESTINATION_FILE" ]]; then
    LEGACY_DEFAULTS="$(mktemp)"
    if defaults export group.com.mlarrosa.HermesAgentWidget "$LEGACY_DEFAULTS" >/dev/null 2>&1; then
        mkdir -p "$SHARED_DESTINATION_DIR"
        if ! plutil -extract 'destinations\.v1' raw -o - "$LEGACY_DEFAULTS" \
            | /usr/bin/base64 -D > "$SHARED_DESTINATION_FILE"; then
            rm -f "$SHARED_DESTINATION_FILE"
        fi
    fi
    rm -f "$LEGACY_DEFAULTS"
fi

if [[ ! -f "$SHARED_INSTALLATION_FILE" ]]; then
    LEGACY_DEFAULTS="$(mktemp)"
    if defaults export group.com.mlarrosa.HermesAgentWidget "$LEGACY_DEFAULTS" >/dev/null 2>&1; then
        mkdir -p "$SHARED_DESTINATION_DIR"
        if ! plutil -extract 'installation\.v1' raw -o - "$LEGACY_DEFAULTS" \
            | /usr/bin/base64 -D > "$SHARED_INSTALLATION_FILE"; then
            rm -f "$SHARED_INSTALLATION_FILE"
        fi
    fi
    rm -f "$LEGACY_DEFAULTS"
fi

REGISTERED=false
for _ in {1..60}; do
    pluginkit -a "$INSTALLED_EXTENSION"
    if pluginkit -m -A -D -v -i "$WIDGET_BUNDLE_ID" | /usr/bin/grep -F "$INSTALLED_EXTENSION" >/dev/null; then
        REGISTERED=true
        break
    fi
    sleep 0.5
done
if [[ "$REGISTERED" != true ]]; then
    printf 'error: PlugInKit did not register %s\n' "$INSTALLED_EXTENSION" >&2
    exit 1
fi

# Force WidgetKit's user daemon to discover the replacement immediately.
killall chronod 2>/dev/null || true
open "$INSTALL_APP"

INSTALLED_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INSTALLED_EXTENSION/Contents/Info.plist")"
printf 'Installed latest Hermes widget build: v%s (%s)\n' "$ACTUAL_VERSION" "$INSTALLED_BUILD"
printf 'App: %s\n' "$INSTALL_APP"