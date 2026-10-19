#!/bin/bash
set -euo pipefail

REPOSITORY_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/build-cleanup.sh
source "$REPOSITORY_DIR/scripts/build-cleanup.sh"

test_root="$(mktemp -d "${TMPDIR:-/tmp}/rede-cleanup-tests.XXXXXXXX")"
test_root="$(cd "$test_root" && pwd -P)"
SCRIPT_DIR="$test_root/workspace"
DERIVED_DATA_PATH="$SCRIPT_DIR/.derivedData-redemac-build"
BUILD_CONFIGURATION="Debug"
mkdir -p "$SCRIPT_DIR"

expect_rejection() {
    local output expected_message="${2:-}"
    if output="$(trash_build_artifact "$1" 2>&1)"; then
        echo "Expected cleanup rejection: $1" >&2
        exit 1
    fi
    if [ -n "$expected_message" ] && [[ "$output" != *"$expected_message"* ]]; then
        echo "Unexpected rejection for $1: $output" >&2
        exit 1
    fi
}

touch "$SCRIPT_DIR/keep.txt"
touch "$test_root/rede-dev-entitlements.unowned"
expect_rejection "$test_root/rede-dev-entitlements.unowned"
expect_rejection "$SCRIPT_DIR/keep.txt"
expect_rejection "$SCRIPT_DIR"
expect_rejection "$HOME"
expect_rejection "/"
expect_rejection "rede.app"
test -f "$SCRIPT_DIR/keep.txt"

adversarial_directory="$(mktemp -d -t rede-codesign-test)"
adversarial_victim="$(mktemp -t rede-cleanup-victim)"
expect_rejection "$adversarial_directory/../$(basename "$adversarial_victim")" "dot path segments"
test -f "$adversarial_victim"
touch "$adversarial_directory/nested"
expect_rejection "$adversarial_directory/nested" "not a build artifact"
test -f "$adversarial_directory/nested"
expect_rejection "$adversarial_directory/./nested" "dot path segments"
expect_rejection "$adversarial_directory/" "trailing slash"

mkdir -p "$SCRIPT_DIR/rede.app/active"
(
    cd "$SCRIPT_DIR/rede.app/active"
    expect_rejection "$SCRIPT_DIR/rede.app" "working directory or its ancestors"
)
test -d "$SCRIPT_DIR/rede.app/active"

mkdir -p "$test_root/foreign.app"
mkdir -p "$test_root/symlink-workspace"
ln -s "$test_root/foreign.app" "$test_root/symlink-workspace/rede.app"
(
    SCRIPT_DIR="$test_root/symlink-workspace"
    expect_rejection "$SCRIPT_DIR/rede.app"
)
test -d "$test_root/foreign.app"

mkdir -p "$test_root/recycle-workspace/rede.app" "$test_root/foreign-recycle"
ln -s "$test_root/foreign-recycle" "$test_root/recycle-workspace/.derivedData-recycle"
(
    SCRIPT_DIR="$test_root/recycle-workspace"
    OSTYPE=linux-gnu expect_rejection "$SCRIPT_DIR/rede.app" "symbolic-link recycle directory"
)
test -d "$test_root/recycle-workspace/rede.app"
test -z "$(ls -A "$test_root/foreign-recycle")"

SCRIPT_DIR="$test_root/another-workspace"
DERIVED_DATA_PATH="$SCRIPT_DIR/.derivedData-redemac-build"
mkdir -p "$SCRIPT_DIR/rede.app"
touch "$SCRIPT_DIR/rede.app/preserved.txt"
OSTYPE=linux-gnu trash_build_artifact "$SCRIPT_DIR/rede.app"
test ! -e "$SCRIPT_DIR/rede.app"
retained_file="$(find "$SCRIPT_DIR/.derivedData-recycle" -name preserved.txt -print)"
test -n "$retained_file"

trash_build_artifact "$SCRIPT_DIR/rede.app"
test -f "$retained_file"

if [[ "$OSTYPE" == darwin* ]] && [ -x /usr/bin/trash ]; then
    mkdir -p "$SCRIPT_DIR/rede.app"
    touch "$SCRIPT_DIR/rede.app/recoverable.txt"
    trash_build_artifact "$SCRIPT_DIR/rede.app"
    test ! -e "$SCRIPT_DIR/rede.app"
    temporary_file="$(mktemp -t rede-dev-entitlements)"
    trash_build_artifact "$temporary_file"
    test ! -e "$temporary_file"
    temporary_directory="$(mktemp -d -t rede-codesign-test)"
    trash_build_artifact "$temporary_directory"
    test ! -e "$temporary_directory"
fi

echo "Build cleanup tests passed. Retained fixtures: $test_root"
