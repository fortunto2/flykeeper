#!/usr/bin/env bash
# App Store screenshots, taken from the running app on the two sizes Apple asks for.
#
#   scripts/screenshots.sh
#
# Scenes are set through the app's own launch environment (FLY_TIER / FLY_FEED / FLY_LIGHTS),
# not by driving the UI: a tap that lands a frame late gives a different picture every run.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=docs/screenshots
mkdir -p "$OUT"

APP=$(xcodebuild -project Flykeeper.xcodeproj -scheme Flykeeper -sdk iphonesimulator \
        -configuration Debug -derivedDataPath build -showBuildSettings 2>/dev/null \
      | awk -F' = ' '/^ *BUILT_PRODUCTS_DIR = /{d=$2} /^ *FULL_PRODUCT_NAME = /{n=$2} END{print d"/"n}')
test -d "$APP" || { echo "no app bundle — run make build first"; exit 1; }

# name:tier:feed:lights:settle seconds
SCENES=(
  "full-brain:full::: 16"
  "eating:full:1:: 24"
  "asleep:full::off: 16"
  "eco:eco:1:: 8"
)

for sim in shot-69 shot-65; do
  udid=$(xcrun simctl list devices available | grep -F "$sim (" | sed -E 's/.*\(([0-9A-F-]+)\).*/\1/' | head -1)
  test -n "$udid" || { echo "simulator $sim not found"; exit 1; }
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
  xcrun simctl install "$udid" "$APP"
  xcrun simctl status_bar "$udid" override --time "9:41" --cellularBars 4 --wifiBars 3 --batteryState charged --batteryLevel 100
  for scene in "${SCENES[@]}"; do
    IFS=':' read -r name tier feed lights settle <<< "$scene"
    xcrun simctl terminate "$udid" co.superduperai.flykeeper 2>/dev/null || true
    env_args=(SIMCTL_CHILD_FLY_TIER="$tier")
    [ -n "$feed" ] && env_args+=(SIMCTL_CHILD_FLY_FEED=1)
    [ -n "$lights" ] && env_args+=(SIMCTL_CHILD_FLY_LIGHTS="$lights")
    env "${env_args[@]}" xcrun simctl launch "$udid" co.superduperai.flykeeper >/dev/null
    sleep "${settle# }"
    xcrun simctl io "$udid" screenshot "$OUT/${sim}-${name}.png" >/dev/null 2>&1
    echo "$OUT/${sim}-${name}.png"
  done
  xcrun simctl terminate "$udid" co.superduperai.flykeeper 2>/dev/null || true
  xcrun simctl shutdown "$udid" 2>/dev/null || true
done
