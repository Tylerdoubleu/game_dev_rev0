#!/usr/bin/env bash
# v0.6.3 web export with a build stamp. Writes scripts/systems/build_info.gd with the short hash of the commit being
# exported (HEAD; "+dirty" if scripts/scenes/assets/project files have uncommitted changes), exports the "Web" preset
# to build/web, copies it to docs/, then restores the "dev" placeholder so the source tree stays clean.
# Usage: tools/export_web.sh [godot-binary]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${1:-godot}"
INFO=scripts/systems/build_info.gd
VERSION=$(sed -n 's/^const VERSION := "\(.*\)"/\1/p' "$INFO")
COMMIT=$(git rev-parse --short=7 HEAD)
if [ -n "$(git status --porcelain -- scripts scenes assets project.godot export_presets.cfg | grep -v " $INFO\$" || true)" ]; then
	COMMIT="$COMMIT+dirty"
fi
BUILT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cp "$INFO" /tmp/build_info.gd.bak
trap 'cp /tmp/build_info.gd.bak "$INFO"' EXIT
sed -i "s/^const COMMIT := \".*\"/const COMMIT := \"$COMMIT\"/; s/^const BUILT_UTC := \".*\"/const BUILT_UTC := \"$BUILT\"/" "$INFO"
echo "build stamp: $VERSION · $COMMIT ($BUILT)"
"$GODOT" --headless --path . --export-release "Web" build/web/index.html
cp build/web/index.* docs/
PCK=$(stat -c %s build/web/index.pck)
grep -q "\"index.pck\":$PCK" build/web/index.html && grep -q "\"index.pck\":$PCK" docs/index.html
echo "exported: index.pck $PCK bytes, stamp $VERSION · $COMMIT"
