#!/bin/bash

# Only artifacts already owned by build.sh are eligible for reversible cleanup.
trash_build_artifact() {
    local target="$1"
    local parent name expected_parent
    expected_parent="$(build_cleanup_expected_parent "$target")" || return 1
    if [ -L "$target" ]; then
        echo "Cleanup refuses a symbolic link: $target" >&2
        return 1
    fi
    if [ ! -e "$target" ]; then
        return 0
    fi
    parent="$(cd "$(dirname "$target")" && pwd -P)" || return 1
    name="$(basename "$target")"
    if [ "$parent" != "$expected_parent" ]; then
        echo "Cleanup parent differs from the expected directory: $target" >&2
        return 1
    fi
    target="$parent/$name"
    case "$(pwd -P)/" in
        "$target/"*) echo "Cleanup refuses the working directory or its ancestors: $target" >&2; return 1 ;;
    esac
    if [[ "$OSTYPE" == darwin* ]] && [ -x /usr/bin/trash ]; then
        /usr/bin/trash -s -v "$target"
    else
        retain_build_artifact "$target"
    fi
}

build_cleanup_expected_parent() {
    local target="$1"
    case "$target" in
        /*) ;;
        *) echo "Cleanup requires an absolute path: $target" >&2; return 1 ;;
    esac
    case "$target/" in
        */../*|*/./*) echo "Cleanup refuses dot path segments: $target" >&2; return 1 ;;
    esac
    case "$target" in
        */) echo "Cleanup refuses a trailing slash: $target" >&2; return 1 ;;
    esac
    case "$target" in
        "$SCRIPT_DIR/rede.app") printf '%s\n' "$SCRIPT_DIR" ;;
        /Applications/rede.app) printf '%s\n' "/Applications" ;;
        "$DERIVED_DATA_PATH/Build/Products/$BUILD_CONFIGURATION/rede.app/Contents/Resources/AppIcon.icon")
            printf '%s\n' "$DERIVED_DATA_PATH/Build/Products/$BUILD_CONFIGURATION/rede.app/Contents/Resources"
            ;;
        *)
            case "$(basename "$target")" in
                rede-codesign-test.?*|rede-dev-entitlements.?*)
                    (cd "${TMPDIR:-/tmp}" && pwd -P)
                    ;;
                *) echo "Cleanup target is not a build artifact: $target" >&2; return 1 ;;
            esac
            ;;
    esac
}

retain_build_artifact() {
    local target="$1"
    local recycle_root="$SCRIPT_DIR/.derivedData-recycle"
    local retained_directory
    if [ -L "$recycle_root" ]; then
        echo "Cleanup refuses a symbolic-link recycle directory: $recycle_root" >&2
        return 1
    fi
    mkdir -p "$recycle_root"
    retained_directory="$(mktemp -d "$recycle_root/retained.XXXXXXXX")"
    mv "$target" "$retained_directory/"
    echo "Retained build artifact: $retained_directory/$(basename "$target")"
}
