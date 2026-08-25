#!/bin/bash
# Cuts a release from whatever is in VERSION, so the tag and the version inside
# the bundle can never drift apart — if they do, the updater loops.
set -e
cd "$(dirname "$0")"

VERSION=$(tr -d " \n" < VERSION)
TAG="v$VERSION"

if gh release view "$TAG" >/dev/null 2>&1; then
    echo "Release $TAG already exists. Bump VERSION first."
    exit 1
fi

./build-app.sh

BUILT=$(plutil -extract CFBundleShortVersionString raw "dist/Notch Counter.app/Contents/Info.plist")
if [ "$BUILT" != "$VERSION" ]; then
    echo "Bundle reports $BUILT but VERSION says $VERSION — refusing to publish."
    exit 1
fi

NOTES="${1:-Update to $VERSION.}"
gh release create "$TAG" dist/NotchCounter.zip --title "$TAG" --notes "$NOTES"
echo
echo "Published $TAG. Everyone running the app sees the update within 6 hours,"
echo "or immediately via the menu bar → Check for updates."
