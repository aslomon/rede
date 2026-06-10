#!/bin/bash
set -euo pipefail

# rede macOS App - Build & Run
# Voraussetzungen: Full Xcode with Command Line Tools, xcodegen

RUN_AFTER=false
INSTALL_APP=false
BUILD_CONFIGURATION="Release"
UNIVERSAL_ARCHS="arm64 x86_64"
LLAMACPP_HELPER_PATH="${LLAMACPP_HELPER_PATH:-}"
LLAMACPP_HELPER_SHA256="${LLAMACPP_HELPER_SHA256:-}"
REQUIRE_LLAMA_CPP_HELPER=false
ALLOW_MISSING_LLAMA_CPP_HELPER=false

for arg in "$@"; do
    case "$arg" in
        --debug)
            BUILD_CONFIGURATION="Debug"
            ;;
        --run)
            RUN_AFTER=true
            ;;
        --install)
            INSTALL_APP=true
            ;;
        --release)
            BUILD_CONFIGURATION="Release"
            ;;
        --llamacpp-helper=*)
            LLAMACPP_HELPER_PATH="${arg#*=}"
            ;;
        --llamacpp-helper-sha256=*)
            LLAMACPP_HELPER_SHA256="${arg#*=}"
            ;;
        --require-llamacpp-helper)
            REQUIRE_LLAMA_CPP_HELPER=true
            ;;
        --allow-missing-llamacpp-helper)
            ALLOW_MISSING_LLAMA_CPP_HELPER=true
            ;;
        *)
            echo "Unbekannte Option: $arg"
            echo "Verwendung: ./build.sh [--install] [--run] [--release] [--debug] [--llamacpp-helper=/path/to/llama-server] [--llamacpp-helper-sha256=<sha256>] [--require-llamacpp-helper] [--allow-missing-llamacpp-helper]"
            exit 1
            ;;
    esac
done

CODESIGN_IDENTITY_NAME="rede Local Dev"
# Absolute path is set after PROJECT_DIR is known (see below).
ENTITLEMENTS_PATH=""
# Resolved once by resolve_codesign_identity(): "stable" or "adhoc".
CODESIGN_MODE="adhoc"

# Decides whether we can sign with the stable local identity or must fall back to
# ad-hoc. Stable signing requires BOTH: the identity exists in the codesigning
# keychain AND a throwaway test-sign with it actually succeeds (covers the case
# where the identity is listed but codesign has no key access yet).
resolve_codesign_identity() {
    if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "$CODESIGN_IDENTITY_NAME"; then
        CODESIGN_MODE="adhoc"
        return
    fi

    local test_dir
    test_dir="$(mktemp -d -t rede-codesign-test)"
    local test_file="$test_dir/codesign-test"
    printf 'rede' > "$test_file"

    if codesign --force --sign "$CODESIGN_IDENTITY_NAME" "$test_file" >/dev/null 2>&1; then
        CODESIGN_MODE="stable"
    else
        CODESIGN_MODE="adhoc"
    fi

    rm -rf "$test_dir"
}

# Signs the app bundle using the resolved mode. Stable mode uses the local
# identity + hardened runtime + entitlements so the CDHash stays constant across
# rebuilds (TCC grants survive). Ad-hoc mode is the clean fallback when no
# identity is installed — the build still succeeds.
sign_app_bundle() {
    local target="$1"
    sign_nested_code "$target"
    sign_sparkle_framework "$target"

    if [ "$CODESIGN_MODE" = "stable" ]; then
        echo "🔏 Signiere mit stabiler lokaler Identitaet (\"$CODESIGN_IDENTITY_NAME\"). Bedienungshilfen-Freigaben ueberleben Rebuilds."
        codesign --force --options runtime \
            --entitlements "$ENTITLEMENTS_PATH" \
            --sign "$CODESIGN_IDENTITY_NAME" "$target" 2>&1
    else
        echo "🔏 Signiere lokale Development-App ad-hoc. Dieses Artefakt ist nicht notarisiert."
        echo "   Tipp: Fuehre einmalig scripts/create-dev-cert.sh aus, damit Bedienungshilfen-Freigaben Rebuilds ueberleben."
        codesign --force --sign - "$target" 2>&1
    fi

    codesign --verify --deep --strict --verbose=2 "$target" >/dev/null 2>&1
}

sign_nested_code() {
    local target="$1"
    local helpers_dir="$target/Contents/Helpers"
    local helper="$helpers_dir/llama-server"

    if [ ! -f "$helper" ]; then
        return
    fi

    local sign_id="-"
    if [ "$CODESIGN_MODE" = "stable" ]; then
        sign_id="$CODESIGN_IDENTITY_NAME"
    fi

    # Sign the bundled dylibs (real files only), then the helper — deliberately WITHOUT the hardened
    # runtime / library validation. llama-server is spawned as a subprocess and must load its own
    # @rpath dylibs, which are signed locally with no shared Team ID; hardened runtime would reject
    # them ("different Team IDs"). A notarized release would instead need Developer ID signing + the
    # com.apple.security.cs.disable-library-validation entitlement on the helper.
    local lib
    for lib in "$helpers_dir"/*.dylib; do
        if [ ! -f "$lib" ] || [ -L "$lib" ]; then
            continue
        fi
        codesign --force --sign "$sign_id" "$lib" >/dev/null 2>&1
    done
    codesign --force --sign "$sign_id" "$helper" 2>&1

    codesign --verify --strict --verbose=2 "$helper" >/dev/null 2>&1
}

# Re-signs the embedded Sparkle.framework's nested executables (XPC services, Autoupdate,
# Updater.app) with the same identity as the app, innermost-first. Without this, the outer
# non-deep app re-sign would reference nested code still carrying the Xcode build signature
# (mismatched identity) and Sparkle's installer would fail signature validation at runtime.
sign_sparkle_framework() {
    local target="$1"
    local fw="$target/Contents/Frameworks/Sparkle.framework"

    if [ ! -d "$fw" ]; then
        return
    fi

    local sign_id="-"
    if [ "$CODESIGN_MODE" = "stable" ]; then
        sign_id="$CODESIGN_IDENTITY_NAME"
    fi

    # XPC services keep their own entitlements (the Downloader is sandboxed by design).
    local xpc
    for xpc in "$fw/Versions/B/XPCServices/"*.xpc; do
        [ -e "$xpc" ] || continue
        codesign --force --options runtime --preserve-metadata=entitlements --sign "$sign_id" "$xpc" 2>&1
    done

    if [ -e "$fw/Versions/B/Autoupdate" ]; then
        codesign --force --options runtime --sign "$sign_id" "$fw/Versions/B/Autoupdate" 2>&1
    fi
    if [ -d "$fw/Versions/B/Updater.app" ]; then
        codesign --force --options runtime --sign "$sign_id" "$fw/Versions/B/Updater.app" 2>&1
    fi

    codesign --force --sign "$sign_id" "$fw" 2>&1
    codesign --verify --strict --verbose=2 "$fw" >/dev/null 2>&1
}

verify_universal_app() {
    local app_path="$1"
    local app_name
    local binary_path
    local archs

    app_name="$(basename "$app_path" .app)"
    binary_path="$app_path/Contents/MacOS/$app_name"

    if [ ! -f "$binary_path" ]; then
        echo "❌ Konnte App-Binary nicht finden: $binary_path"
        exit 1
    fi

    archs="$(lipo -archs "$binary_path" 2>/dev/null || true)"

    if [[ -z "$archs" ]]; then
        echo "❌ Konnte Architekturen nicht lesen: $binary_path"
        file "$binary_path" 2>/dev/null || true
        exit 1
    fi

    if [[ " $archs " != *" arm64 "* || " $archs " != *" x86_64 "* ]]; then
        echo "❌ Build ist nicht universal. Erwartet: arm64 + x86_64"
        echo "   Gefunden: $archs"
        file "$binary_path" 2>/dev/null || true
        exit 1
    fi

    echo "✅ Universal Binary verifiziert: $archs"
}

verify_llamacpp_helper() {
    local helper_path="$1"
    local expected_sha="$2"
    local archs
    local actual_sha

    if [ ! -f "$helper_path" ]; then
        echo "❌ llama.cpp Helper nicht gefunden: $helper_path"
        exit 1
    fi

    if [[ "$helper_path" != /* ]]; then
        echo "❌ llama.cpp Helper-Pfad muss absolut sein: $helper_path"
        exit 1
    fi

    if [ -L "$helper_path" ]; then
        echo "❌ llama.cpp Helper darf kein Symlink sein: $helper_path"
        exit 1
    fi

    if [ ! -x "$helper_path" ]; then
        echo "❌ llama.cpp Helper ist nicht ausfuehrbar: $helper_path"
        exit 1
    fi

    if [ -z "$expected_sha" ]; then
        echo "❌ llama.cpp Helper braucht eine erwartete SHA-256."
        echo "   Nutze: --llamacpp-helper-sha256=<sha256>"
        exit 1
    fi

    actual_sha="$(shasum -a 256 "$helper_path" | awk '{print $1}')"
    if [ "$actual_sha" != "$expected_sha" ]; then
        echo "❌ llama.cpp Helper Checksum passt nicht."
        echo "   Erwartet: $expected_sha"
        echo "   Gefunden: $actual_sha"
        exit 1
    fi

    archs="$(lipo -archs "$helper_path" 2>/dev/null || true)"
    if [[ -z "$archs" ]]; then
        echo "❌ Konnte Helper-Architekturen nicht lesen: $helper_path"
        file "$helper_path" 2>/dev/null || true
        exit 1
    fi

    if [[ " $archs " != *" arm64 "* || " $archs " != *" x86_64 "* ]]; then
        echo "❌ llama.cpp Helper ist nicht universal. Erwartet: arm64 + x86_64"
        echo "   Gefunden: $archs"
        file "$helper_path" 2>/dev/null || true
        exit 1
    fi

    echo "✅ llama.cpp Helper verifiziert: $archs"
}

stage_llamacpp_helper() {
    local app_path="$1"

    if [ -z "$LLAMACPP_HELPER_PATH" ]; then
        echo "⚠️  Kein llama.cpp Helper angegeben – App baut ohne gebuendelten lokalen LLM-Helper."
        return
    fi

    verify_llamacpp_helper "$LLAMACPP_HELPER_PATH" "$LLAMACPP_HELPER_SHA256"
    local helpers_dir="$app_path/Contents/Helpers"
    mkdir -p "$helpers_dir"
    cp -f "$LLAMACPP_HELPER_PATH" "$helpers_dir/llama-server"
    chmod 755 "$helpers_dir/llama-server"
    # Bundle the helper's companion dylibs (same directory), preserving symlinks, so the
    # dynamically-linked llama-server can resolve @rpath/lib*.dylib at runtime.
    local helper_src_dir lib
    helper_src_dir="$(dirname "$LLAMACPP_HELPER_PATH")"
    for lib in "$helper_src_dir"/*.dylib; do
        [ -e "$lib" ] || continue
        cp -a "$lib" "$helpers_dir/"
    done
    verify_llamacpp_helper "$helpers_dir/llama-server" "$LLAMACPP_HELPER_SHA256"
}

preflight_llamacpp_helper_requirement() {
    if [ -n "$LLAMACPP_HELPER_PATH" ]; then
        return
    fi

    if [ "$REQUIRE_LLAMA_CPP_HELPER" = true ] || { [ "$BUILD_CONFIGURATION" = "Release" ] && [ "$ALLOW_MISSING_LLAMA_CPP_HELPER" != true ]; } || { [ "$INSTALL_APP" = true ] && [ "$ALLOW_MISSING_LLAMA_CPP_HELPER" != true ]; }; then
        echo "❌ llama.cpp Helper ist fuer diesen Build erforderlich."
        echo "   Nutze: ./build.sh --llamacpp-helper=/absolute/path/to/llama-server --llamacpp-helper-sha256=<sha256>"
        echo "   Nur fuer lokale Zwischenbuilds: --allow-missing-llamacpp-helper"
        exit 1
    fi
}

ensure_xcodebuild_available() {
    if xcodebuild -version >/dev/null 2>&1; then
        return
    fi

    local default_xcode="/Applications/Xcode.app/Contents/Developer"
    if [ -d "$default_xcode" ]; then
        export DEVELOPER_DIR="$default_xcode"
        if xcodebuild -version >/dev/null 2>&1; then
            echo "⚠️  Aktiver Developer-Pfad nutzt kein vollständiges Xcode. Verwende: $DEVELOPER_DIR"
            return
        fi
    fi

    echo "❌ xcodebuild ist nicht verfügbar."
    echo "   Installiere Xcode und wähle es mit:"
    echo "   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    exit 1
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/BlitztextMac"
PROJECT_FILE="$PROJECT_DIR/BlitztextMac.xcodeproj"
DERIVED_DATA_PATH="$SCRIPT_DIR/.derivedData-blitztextmac-build"
ENTITLEMENTS_PATH="$PROJECT_DIR/Resources/BlitztextMac.entitlements"
cd "$PROJECT_DIR"

preflight_llamacpp_helper_requirement
ensure_xcodebuild_available

if command -v xcodegen &> /dev/null; then
    echo "⚙️  Generiere Xcode-Projekt ..."
    xcodegen generate 2>&1
elif [ -d "$PROJECT_FILE" ]; then
    echo "⚠️  xcodegen nicht gefunden – nutze vorhandenes Xcode-Projekt."
else
    echo "❌ xcodegen fehlt."
    echo "   Installiere xcodegen explizit mit:"
    echo "   brew install xcodegen"
    echo "   Oder stelle sicher, dass $PROJECT_FILE vorhanden ist."
    exit 1
fi

# Bauen
echo "🔨 Baue rede ..."
# ENABLE_DEBUG_DYLIB=NO: Xcode 16 splits Debug builds into a launcher + rede.debug.dylib.
# Our standalone re-sign (sign_app_bundle) signs the bundle non-deep, so the nested debug dylib
# keeps its original signature → mismatched Team IDs → dyld aborts at launch. Forcing a single
# merged binary (as Release already is) keeps `--debug` builds launchable outside Xcode. No-op for
# Release. Does NOT affect Xcode's own interactive builds/previews (this only constrains build.sh).
xcodebuild \
    -project BlitztextMac.xcodeproj \
    -scheme BlitztextMac \
    -destination 'platform=macOS' \
    -configuration "$BUILD_CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    ONLY_ACTIVE_ARCH=NO \
    ARCHS="$UNIVERSAL_ARCHS" \
    ENABLE_DEBUG_DYLIB=NO \
    clean build

# App finden
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$BUILD_CONFIGURATION/rede.app"

if [ ! -d "$APP_PATH" ]; then
    echo "❌ Build fehlgeschlagen – keine App gefunden."
    exit 1
fi

verify_universal_app "$APP_PATH"

# Resources manuell ins Bundle kopieren (xcodegen kopiert sie nicht automatisch)
echo "📋 Kopiere Resources ..."
RESOURCES_DIR="$APP_PATH/Contents/Resources"
mkdir -p "$RESOURCES_DIR"
cp -f "$PROJECT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/" 2>/dev/null || true
if [ -d "$PROJECT_DIR/Resources/AppIcon.icon" ]; then
    rm -rf "$RESOURCES_DIR/AppIcon.icon"
    ditto "$PROJECT_DIR/Resources/AppIcon.icon" "$RESOURCES_DIR/AppIcon.icon"
fi
cp -f "$PROJECT_DIR/Resources/menubar_icon.png" "$RESOURCES_DIR/" 2>/dev/null || true
cp -f "$PROJECT_DIR/Resources/menubar_icon@2x.png" "$RESOURCES_DIR/" 2>/dev/null || true
stage_llamacpp_helper "$APP_PATH"

# In Projektordner kopieren
DEST="$SCRIPT_DIR/rede.app"
rm -rf "$DEST"
cp -R "$APP_PATH" "$DEST"
resolve_codesign_identity
sign_app_bundle "$DEST"
verify_universal_app "$DEST"

RUN_TARGET="$DEST"

if [ "$INSTALL_APP" = true ]; then
    APPS_DIR="/Applications"
    INSTALL_DEST="$APPS_DIR/rede.app"
    if [ ! -w "$APPS_DIR" ]; then
        echo "❌ /Applications ist nicht beschreibbar."
        echo "   Fuehre den Befehl mit passenden Rechten erneut aus oder ziehe die App manuell nach /Applications."
        exit 1
    fi
    rm -rf "$INSTALL_DEST"
    cp -R "$DEST" "$INSTALL_DEST"
    sign_app_bundle "$INSTALL_DEST"
    verify_universal_app "$INSTALL_DEST"
    RUN_TARGET="$INSTALL_DEST"
fi

echo ""
echo "✅ Fertig! App liegt unter:"
echo "   $DEST"
if [ "$INSTALL_APP" = true ]; then
    echo "   $RUN_TARGET"
fi
echo ""
echo "Build-Typ: $BUILD_CONFIGURATION"
echo "Architekturen: $UNIVERSAL_ARCHS"
echo "Kompatibel: Apple Silicon + Intel (macOS 14+)"
echo ""
echo "Naechste Schritte:"
echo "1. App starten"
echo "2. Mikrofon erlauben"
echo "3. Fuer direktes Einfuegen zusaetzlich Bedienungshilfen erlauben"
echo "4. In rede deinen eigenen OpenAI API Key eintragen"
echo "5. Loslegen und bei Bedarf im Code weiterbauen"
echo ""

# Optional: direkt starten
if [ "$RUN_AFTER" = true ]; then
    echo "🚀 Starte rede ..."
    open "$RUN_TARGET"
fi
