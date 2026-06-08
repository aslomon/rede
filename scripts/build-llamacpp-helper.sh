#!/bin/bash
set -euo pipefail

# Builds a pinned universal macOS llama.cpp `llama-server` helper for Blitztext packaging.
# Default path uses official llama.cpp macOS release tarballs and combines arm64+x64 via lipo.
# Generated files stay in .derivedData-llamacpp-helper/ and are not tracked.

LLAMACPP_REPO="${LLAMACPP_REPO:-https://github.com/ggml-org/llama.cpp.git}"
LLAMACPP_REF="${LLAMACPP_REF:-b9360}"
UNIVERSAL_ARCHS="${UNIVERSAL_ARCHS:-arm64;x86_64}"
FROM_SOURCE=false
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK_DIR="${LLAMACPP_WORK_DIR:-$ROOT_DIR/.derivedData-llamacpp-helper}"
SRC_DIR="$WORK_DIR/src"
BUILD_DIR="$WORK_DIR/build-$LLAMACPP_REF"
OUTPUT_DIR="$WORK_DIR/output"
OUTPUT_HELPER="$OUTPUT_DIR/llama-server"

usage() {
    echo "Usage: $0 [--ref <llama.cpp-release-or-commit>] [--repo <git-url>] [--from-source]"
    echo ""
    echo "Environment:"
    echo "  LLAMACPP_REF       llama.cpp release tag/commit (default: b9360)"
    echo "  LLAMACPP_REPO      git repository URL"
    echo "  UNIVERSAL_ARCHS    CMAKE_OSX_ARCHITECTURES value for --from-source"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --ref)
            LLAMACPP_REF="$2"
            shift 2
            ;;
        --repo)
            LLAMACPP_REPO="$2"
            shift 2
            ;;
        --from-source)
            FROM_SOURCE=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1"
        exit 1
    fi
}

find_helper() {
    local directory="$1"
    find "$directory" -type f -name llama-server -print | head -1
}

build_from_source() {
    require_command git
    require_command cmake

    if [ ! -d "$SRC_DIR/.git" ]; then
        git clone --filter=blob:none "$LLAMACPP_REPO" "$SRC_DIR"
    fi

    git -C "$SRC_DIR" fetch --tags --force
    git -C "$SRC_DIR" checkout --force "$LLAMACPP_REF"
    git -C "$SRC_DIR" submodule update --init --recursive

    rm -rf "$BUILD_DIR"
    cmake -S "$SRC_DIR" -B "$BUILD_DIR" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_OSX_ARCHITECTURES="$UNIVERSAL_ARCHS" \
        -DGGML_NATIVE=OFF \
        -DLLAMA_CURL=OFF

    cmake --build "$BUILD_DIR" --config Release --target llama-server --parallel

    local built_helper
    built_helper="$(find_helper "$BUILD_DIR")"
    if [ -z "$built_helper" ]; then
        echo "Could not find built llama-server in $BUILD_DIR"
        exit 1
    fi
    cp -f "$built_helper" "$OUTPUT_HELPER"
}

build_from_release_artifacts() {
    require_command curl
    require_command tar

    local arm_archive="$WORK_DIR/llama-$LLAMACPP_REF-bin-macos-arm64.tar.gz"
    local x64_archive="$WORK_DIR/llama-$LLAMACPP_REF-bin-macos-x64.tar.gz"
    local arm_dir="$WORK_DIR/extract-$LLAMACPP_REF-arm64"
    local x64_dir="$WORK_DIR/extract-$LLAMACPP_REF-x64"
    local arm_url="https://github.com/ggml-org/llama.cpp/releases/download/$LLAMACPP_REF/llama-$LLAMACPP_REF-bin-macos-arm64.tar.gz"
    local x64_url="https://github.com/ggml-org/llama.cpp/releases/download/$LLAMACPP_REF/llama-$LLAMACPP_REF-bin-macos-x64.tar.gz"

    curl -L --fail -o "$arm_archive" "$arm_url"
    curl -L --fail -o "$x64_archive" "$x64_url"

    rm -rf "$arm_dir" "$x64_dir"
    mkdir -p "$arm_dir" "$x64_dir"
    tar -xzf "$arm_archive" -C "$arm_dir"
    tar -xzf "$x64_archive" -C "$x64_dir"

    local arm_helper
    local x64_helper
    arm_helper="$(find_helper "$arm_dir")"
    x64_helper="$(find_helper "$x64_dir")"

    if [ -z "$arm_helper" ] || [ -z "$x64_helper" ]; then
        echo "Could not find llama-server in downloaded release artifacts."
        exit 1
    fi

    lipo -create "$arm_helper" "$x64_helper" -output "$OUTPUT_HELPER"
}

require_command lipo
require_command shasum
mkdir -p "$WORK_DIR" "$OUTPUT_DIR"

if [ "$FROM_SOURCE" = true ]; then
    build_from_source
else
    build_from_release_artifacts
fi

chmod 755 "$OUTPUT_HELPER"

ARCHS="$(lipo -archs "$OUTPUT_HELPER")"
if [[ " $ARCHS " != *" arm64 "* || " $ARCHS " != *" x86_64 "* ]]; then
    echo "Built helper is not universal. Found: $ARCHS"
    exit 1
fi

SHA256="$(shasum -a 256 "$OUTPUT_HELPER" | awk '{print $1}')"

echo ""
echo "llama-server built successfully"
echo "Path:   $OUTPUT_HELPER"
echo "Archs:  $ARCHS"
echo "SHA256: $SHA256"
echo ""
echo "Package with:"
echo "./build.sh --release --llamacpp-helper=\"$OUTPUT_HELPER\" --llamacpp-helper-sha256=\"$SHA256\""
