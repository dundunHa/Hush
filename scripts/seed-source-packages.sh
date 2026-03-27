#!/bin/bash

set -euo pipefail

target_dir="${1:?usage: seed-source-packages.sh <target-dir>}"
derived_data_root="${HOME}/Library/Developer/Xcode/DerivedData"

is_complete_cache() {
    local dir="$1"

    [[ -d "$dir/checkouts/GRDB.swift/.git" ]] || return 1
    [[ -f "$dir/checkouts/GRDB.swift/SQLiteCustom/src/.git" ]] || return 1
    [[ -d "$dir/checkouts/GRDB.swift/.git/modules/SQLiteCustom/src" ]] || return 1
    [[ -d "$dir/checkouts/swift-markdown/.git" ]] || return 1
    [[ -d "$dir/checkouts/swift-cmark/.git" ]] || return 1
    [[ -d "$dir/checkouts/SwiftMath/.git" ]] || return 1
    [[ -f "$dir/repositories/GRDB.swift-dd0599db/HEAD" ]] || return 1
    [[ -f "$dir/repositories/swift-markdown-5ccdcf70/HEAD" ]] || return 1
    [[ -f "$dir/repositories/swift-cmark-8e53c1c0/HEAD" ]] || return 1
    [[ -f "$dir/repositories/SwiftMath-843ed1ef/HEAD" ]] || return 1
}

find_seed_cache() {
    local best_dir=""
    local best_mtime=0

    [[ -d "$derived_data_root" ]] || return 1

    shopt -s nullglob
    for candidate in "$derived_data_root"/*/SourcePackages; do
        is_complete_cache "$candidate" || continue

        local stamp="$candidate/workspace-state.json"
        local mtime
        if [[ -f "$stamp" ]]; then
            mtime="$(stat -f '%m' "$stamp")"
        else
            mtime="$(stat -f '%m' "$candidate")"
        fi

        if (( mtime > best_mtime )); then
            best_dir="$candidate"
            best_mtime="$mtime"
        fi
    done
    shopt -u nullglob

    [[ -n "$best_dir" ]] || return 1
    printf '%s\n' "$best_dir"
}

mkdir -p "$target_dir"

if is_complete_cache "$target_dir"; then
    exit 0
fi

if ! seed_dir="$(find_seed_cache)"; then
    exit 0
fi

if [[ "$seed_dir" == "$target_dir" ]]; then
    exit 0
fi

echo "Seeding SwiftPM cache from $seed_dir"
rsync -a "$seed_dir"/ "$target_dir"/
