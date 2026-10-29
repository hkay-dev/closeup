#!/usr/bin/env bash
# Publishes a GitHub release from this Mac (there's no CI): a universal build stamped with the version,
# Closeup.dmg (drag to Applications) and Closeup.zip. The build is ad-hoc signed and not notarized,
# so the notes point at the Open Anyway steps.
# Usage: scripts/release.sh [vX.Y.Z]   (default: the last v tag with its last number plus one, or v0.1.0)
set -euo pipefail
cd "$(dirname "$0")/.."

repo='hkay-dev/closeup'
fail() { printf 'release: %s\n' "$*" >&2; exit 1; }

[[ -z "$(git status --porcelain --untracked-files=no)" ]] || fail "the tree has uncommitted changes"
git fetch -q origin main
head=$(git rev-parse HEAD)
git merge-base --is-ancestor "$head" origin/main || fail "HEAD isn't on origin/main yet, so the tag would point at code GitHub doesn't have"

version=${1:-}
if [[ -z "$version" ]]; then
    last=$(git ls-remote --tags --refs origin 'v*' | sed 's|.*refs/tags/||' | sort -V | tail -n 1)
    if [[ -z "$last" ]]; then
        version=v0.1.0
    else
        version="${last%.*}.$(( ${last##*.} + 1 ))"
    fi
fi
[[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must look like v1.2.3, not $version"
if gh release view "$version" -R "$repo" >/dev/null 2>&1; then fail "$version is already released"; fi

UNIVERSAL=1 APP_VERSION="$version" APP_BUILD="$(git rev-list --count HEAD)" scripts/build-app.sh >/dev/null
for arch in arm64 x86_64; do
    lipo build/Closeup.app/Contents/MacOS/Closeup -verify_arch "$arch" || fail "the app has no $arch build"
done
scripts/make-dmg.sh build/Closeup.app build/Closeup.dmg >/dev/null
rm -f build/Closeup.zip
ditto -c -k --keepParent build/Closeup.app build/Closeup.zip

notes=$(mktemp "${TMPDIR:-/tmp}/closeup-notes.XXXXXX")
trap 'rm -f "$notes"' EXIT
cat > "$notes" <<EOF
Download **Closeup.dmg**, open it and drag Closeup into Applications. It runs on Apple silicon and Intel Macs with macOS 13 or later.

This build isn't notarized, so macOS blocks the first open. Open it once, then go to **System Settings › Privacy & Security** and click **Open Anyway** next to "Closeup" was blocked. You do this again after each update.
EOF

gh release create "$version" build/Closeup.dmg build/Closeup.zip -R "$repo" --target "$head" \
    --title "Closeup ${version#v}" --notes-file "$notes"
