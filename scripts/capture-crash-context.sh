#!/bin/bash

set -euo pipefail

APP_NAME="${APP_NAME:-Hush}"
OUTPUT_ROOT="${1:-.build/crash}"
LOG_LOOKBACK="${CRASH_LOG_LOOKBACK:-15m}"
REPORT_LIMIT="${CRASH_REPORT_LIMIT:-3}"
DIAGNOSTIC_DIR="${HOME}/Library/Logs/DiagnosticReports"

timestamp="$(date '+%Y%m%d-%H%M%S')"
run_dir="${OUTPUT_ROOT%/}/${timestamp}"
reports_dir="${run_dir}/reports"
mkdir -p "$reports_dir"

latest_report=""

collect_reports() {
    local candidates
    candidates="$(
        find "$DIAGNOSTIC_DIR" -type f \( -name "${APP_NAME}*.ips" -o -name "${APP_NAME}*.crash" \) -print 2>/dev/null \
            | while IFS= read -r file; do
                printf '%s\t%s\n' "$(stat -f '%m' "$file")" "$file"
            done \
            | sort -rn \
            | head -n "$REPORT_LIMIT"
    )"

    if [ -z "$candidates" ]; then
        return 1
    fi

    while IFS=$'\t' read -r _ file; do
        [ -n "$file" ] || continue
        cp "$file" "$reports_dir/"
        if [ -z "$latest_report" ]; then
            latest_report="$file"
        fi
    done <<<"$candidates"
}

write_summary() {
    local summary_file="$run_dir/summary.txt"
    {
        echo "App: $APP_NAME"
        echo "Captured at: $(date '+%Y-%m-%d %H:%M:%S %z')"
        echo "Workspace: $(pwd)"
        echo "Git commit: $(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
        echo "OS: $(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
        echo

        if [ -n "$latest_report" ]; then
            echo "Latest crash report: $latest_report"
            echo
            if [[ "$latest_report" == *.ips ]]; then
                python3 - "$latest_report" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    _ = json.loads(handle.readline())
    payload = json.load(handle)

exception = payload.get("exception", {})
termination = payload.get("termination", {})
print(
    "Exception: "
    f"{exception.get('type', 'unknown')} / {exception.get('signal', 'unknown')}"
)
print(
    "Termination: "
    f"{termination.get('indicator', 'unknown')} "
    f"(namespace={termination.get('namespace', 'unknown')}, code={termination.get('code', 'unknown')})"
)
print()
print("Triggered thread frames:")

thread = next((item for item in payload.get("threads", []) if item.get("triggered")), None)
frames = []
if thread:
    for frame in thread.get("frames", []):
        symbol = frame.get("symbol")
        source_file = frame.get("sourceFile")
        source_line = frame.get("sourceLine")
        if source_file or symbol:
            if source_file and source_line:
                frames.append(f"- {symbol} ({source_file}:{source_line})")
            elif source_file:
                frames.append(f"- {symbol} ({source_file})")
            elif symbol:
                frames.append(f"- {symbol}")

for item in frames[:10]:
    print(item)
PY
            else
                echo "Likely crash signature:"
                rg -n -m 3 'Exception Type:|Termination Reason:|abort\(\)|swift_abortRetainUnowned|fatal error' "$latest_report" || true
                echo
                echo "Triggered thread frames:"
                rg -n -m 10 '^\\d+\\s' "$latest_report" || true
            fi
        else
            echo "Latest crash report: not found"
        fi
    } >"$summary_file"
}

write_logs() {
    local logs_file="$run_dir/unified.log"
    local predicate="process == \"$APP_NAME\" OR subsystem == \"com.hush.app\""
    if ! log show --last "$LOG_LOOKBACK" --style compact --predicate "$predicate" >"$logs_file" 2>&1; then
        printf 'log show failed for predicate: %s\n' "$predicate" >"$logs_file"
    fi
}

write_manifest() {
    local manifest_file="$run_dir/README.txt"
    {
        echo "Crash context bundle generated for $APP_NAME."
        echo
        echo "Files:"
        echo "- summary.txt: quick signature and top app frames"
        echo "- unified.log: recent system/app logs"
        echo "- reports/: copied crash reports (.ips/.crash)"
        echo
        echo "Suggested workflow:"
        echo "1. Reproduce the crash."
        echo "2. Run 'make crash-context'."
        echo "3. Inspect summary.txt first, then the newest report under reports/."
    } >"$manifest_file"
}

if [ ! -d "$DIAGNOSTIC_DIR" ]; then
    printf 'DiagnosticReports directory not found: %s\n' "$DIAGNOSTIC_DIR" >&2
    exit 1
fi

collect_reports || true
write_summary
write_logs
write_manifest

printf 'Crash context saved to %s\n' "$run_dir"
if [ -n "$latest_report" ]; then
    printf 'Latest crash report copied from %s\n' "$latest_report"
else
    printf 'No %s crash reports were found under %s\n' "$APP_NAME" "$DIAGNOSTIC_DIR"
fi
