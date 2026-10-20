#!/usr/bin/env bash
# Builds scrcpy-server v5.0.1 with server/webcam.patch into build/scrcpy-server-webcam.jar.
set -euo pipefail
cd "$(dirname "$0")/.."

tag=v5.0.1
commit=a60891aea193d92e7e5c3942700eca63f9d19a5f
version=5.0.1-webcam.1
patch=server/webcam.patch
src=build/cache/scrcpy-src
work=build/cache/scrcpy-webcam
out=build/scrcpy-server-webcam.jar

if [[ -f "$out" && "$out" -nt "$patch" && "$out" -nt scripts/build-server.sh ]]; then
    exit 0
fi

if [[ ! -d "$src/.git" ]]; then
    rm -rf "$src"
    mkdir -p build/cache
    echo "Cloning scrcpy $tag."
    git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$tag" https://github.com/Genymobile/scrcpy.git "$src"
fi
actual=$(git -C "$src" rev-parse HEAD)
if [[ "$actual" != "$commit" ]]; then
    echo "$src is at $actual, expected scrcpy $tag ($commit). Delete it and run again." >&2
    exit 1
fi

# A clean copy of the tag, ignoring any local edits in the checkout
rm -rf "$work"
mkdir -p "$work/out"
git -C "$src" archive HEAD | tar -x -C "$work"
git init --quiet "$work"
git -C "$work" apply "$PWD/$patch"

build_script=$work/server/build_without_gradle.sh
sed -i '' "s/^SCRCPY_VERSION_NAME=.*/SCRCPY_VERSION_NAME=$version/" "$build_script"
if ! grep -qx "SCRCPY_VERSION_NAME=$version" "$build_script"; then
    echo "Could not set the version name in $build_script" >&2
    exit 1
fi

export ANDROID_HOME=${ANDROID_HOME:-$HOME/Library/Android/sdk}
if [[ -z "${JAVA_HOME:-}" ]]; then
    JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home'
    if [[ ! -d "$JAVA_HOME" ]]; then
        JAVA_HOME=$(brew --prefix openjdk@17)
    fi
fi
export JAVA_HOME
export PATH="$JAVA_HOME/bin:$PATH"

BUILD_DIR="$work/out" "$build_script"
cp "$work/out/scrcpy-server" "$out.tmp"
mv "$out.tmp" "$out"
echo "Built $out ($version)."
