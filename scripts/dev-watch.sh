#!/usr/bin/env bash
set -euo pipefail

PROJECT="${1:-Hush.xcodeproj}"
SCHEME="${2:-Hush}"
DERIVED_DATA="${3:-.build/DerivedData}"
SPM_DIR="${4:-.build/SourcePackages}"
APP_PATH="${5:-.build/DerivedData/Build/Products/Debug/Hush.app}"

if [ "$#" -ge 5 ]; then
    shift 5
else
    shift "$#" || true
fi

WATCH_DIRS=("$@")
if [ "${#WATCH_DIRS[@]}" -eq 0 ]; then
    WATCH_DIRS=("$(pwd)/Hush" "$(pwd)/HushTests")
fi

EXISTING_WATCH_DIRS=()
for dir in "${WATCH_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        EXISTING_WATCH_DIRS+=("$dir")
    else
        echo "[dev] Skip missing watch path: $dir"
    fi
done

if [ "${#EXISTING_WATCH_DIRS[@]}" -eq 0 ]; then
    echo "[dev] No valid watch directories found."
    exit 1
fi

build_app() {
    mkdir -p "$DERIVED_DATA" "$SPM_DIR"
    xcodebuild \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Debug \
        -derivedDataPath "$DERIVED_DATA" \
        -clonedSourcePackagesDirPath "$SPM_DIR" \
        build
}

launch_app() {
    local app_name
    app_name="$(basename "$APP_PATH" .app)"

    if [ ! -d "$APP_PATH" ]; then
        echo "[dev] App bundle not found: $APP_PATH"
        return 1
    fi

    pkill -x "$app_name" >/dev/null 2>&1 || true
    open -n "$APP_PATH"
}

trap 'echo "[dev] Stopped."; exit 0' INT TERM

echo "[dev] Initial build..."
build_app
echo "[dev] Launching app..."
launch_app

echo "[dev] Watching for changes:"
printf '  - %s\n' "${EXISTING_WATCH_DIRS[@]}"
echo "[dev] Press Ctrl+C to stop."

fswatch -o --latency 0.5 "${EXISTING_WATCH_DIRS[@]}" | while read -r _; do
    echo "[dev] Change detected. Rebuilding..."
    if build_app; then
        echo "[dev] Build succeeded. Restarting app..."
        launch_app || true
    else
        echo "[dev] Build failed. App was not restarted."
    fi
done
