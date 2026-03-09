#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import statistics
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from pathlib import Path

DEFAULT_DERIVED_DATA = Path(os.environ.get("HUSH_DERIVED_DATA", "/tmp/hush-dd"))


@dataclass(frozen=True)
class Window:
    start_s: float
    end_s: float


def _run(cmd: list[str]) -> None:
    subprocess.check_call(cmd)


def _capture(cmd: list[str]) -> str:
    return subprocess.check_output(cmd, text=True)


def _extract_id_value_map(root: ET.Element) -> dict[str, str]:
    values: dict[str, str] = {}
    for el in root.iter():
        el_id = el.get("id")
        if el_id and el.text is not None:
            values[el_id] = el.text
    return values


def _resolve_text(el: ET.Element, id_values: dict[str, str]) -> str | None:
    if el.text is not None:
        return el.text
    ref = el.get("ref")
    if ref:
        return id_values.get(ref)
    return None


def _parse_process_live_series(process_live_xml: Path, mnemonic: str) -> list[tuple[float, int]]:
    tree = ET.parse(process_live_xml)
    root = tree.getroot()
    id_values = _extract_id_value_map(root)

    node = root.find(".//node")
    if node is None:
        raise RuntimeError("Missing <node> in exported XML")

    schema = node.find("schema")
    if schema is None:
        raise RuntimeError("Missing <schema> in exported XML")

    cols = [col.findtext("mnemonic") for col in schema.findall("col")]
    if "start" not in cols:
        raise RuntimeError("Missing 'start' column in schema")
    if mnemonic not in cols:
        raise RuntimeError(f"Missing '{mnemonic}' column in schema")

    idx_time = cols.index("start")
    idx_value = cols.index(mnemonic)

    series: list[tuple[float, int]] = []
    for row in node.findall("row"):
        children = list(row)
        if idx_time >= len(children) or idx_value >= len(children):
            continue
        time_el = children[idx_time]
        value_el = children[idx_value]

        time_text = _resolve_text(time_el, id_values)
        value_text = _resolve_text(value_el, id_values)
        if time_text is None or value_text is None:
            continue

        try:
            time_ns = int(time_text)
            value_bytes = int(value_text)
        except ValueError:
            continue

        series.append((time_ns / 1_000_000_000.0, value_bytes))

    series.sort(key=lambda x: x[0])
    return series


def _select_window(series: list[tuple[float, int]], window: Window) -> list[int]:
    return [v for (t, v) in series if window.start_s <= t <= window.end_s]


def _fmt_mib(value_bytes: float) -> str:
    return f"{value_bytes / (1024 * 1024):.2f} MiB"


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Use xcrun xctrace (Instruments CLI) to record Activity Monitor metrics and estimate the "
            "memory delta after warming 3 hot scenes.\n\n"
            "Notes:\n"
            "- This script launches the Debug app executable, attaches xctrace, records for a fixed duration, "
            "then exports 'activity-monitor-process-live' and computes memory-physical-footprint deltas.\n"
            "- The produced .trace can contain environment info; treat it as sensitive and keep it under .build/.\n"
        )
    )
    parser.add_argument(
        "--app-exec",
        default=str(
            DEFAULT_DERIVED_DATA / "Build/Products/Debug/Hush.app/Contents/MacOS/Hush"
        ),
        help="Path to the app executable to launch (default: Debug build product).",
    )
    parser.add_argument(
        "--duration-s",
        type=float,
        default=45.0,
        help="Recording duration in seconds (default: 45).",
    )
    parser.add_argument(
        "--baseline",
        default="5,12",
        help="Baseline window as 'start,end' seconds (default: 5,12).",
    )
    parser.add_argument(
        "--hot",
        default="30,45",
        help="Hot window as 'start,end' seconds (default: 30,45).",
    )
    parser.add_argument(
        "--output-dir",
        default="/tmp/hush-xctrace",
        help="Directory for trace and exports (default: /tmp/hush-xctrace).",
    )
    parser.add_argument(
        "--automation",
        action="store_true",
        help="Run a debug automation scenario inside the app (no manual UI switching).",
    )
    parser.add_argument(
        "--auto-windows",
        action="store_true",
        help="Derive baseline/hot windows as fractions of the recording duration.",
    )
    parser.add_argument(
        "--db-path",
        default="",
        help="In automation mode, set HUSH_DB_PATH to this SQLite file path (default: under output-dir).",
    )
    parser.add_argument(
        "--expected-min-mib",
        type=float,
        default=None,
        help="Expected minimum memory delta in MiB (default: 0 in --automation, 5 otherwise).",
    )
    parser.add_argument(
        "--expected-max-mib",
        type=float,
        default=None,
        help="Expected maximum memory delta in MiB (default: 15).",
    )
    parser.add_argument(
        "--assert-range",
        action="store_true",
        help="Exit non-zero if delta is outside the expected MiB range.",
    )
    parser.add_argument(
        "--keep-running",
        action="store_true",
        help="Do not kill the app process after recording.",
    )
    args = parser.parse_args()

    app_exec = Path(args.app_exec).expanduser().resolve()
    if not app_exec.exists():
        print(f"App executable not found: {app_exec}", file=sys.stderr)
        print("Hint: run `make build` first.", file=sys.stderr)
        return 2

    duration_s = float(args.duration_s)

    if args.automation and not args.auto_windows:
        args.auto_windows = True
    if args.automation and not args.assert_range:
        args.assert_range = True

    if args.expected_max_mib is None:
        args.expected_max_mib = 15.0
    if args.expected_min_mib is None:
        args.expected_min_mib = 0.0 if args.automation else 5.0

    if args.auto_windows:
        # Leave some time to launch/seed, then sample stable baseline and hot phases.
        baseline = Window(start_s=duration_s * 0.20, end_s=duration_s * 0.40)
        hot = Window(start_s=duration_s * 0.70, end_s=duration_s * 0.90)
    else:
        try:
            baseline_start, baseline_end = (float(x) for x in args.baseline.split(",", 1))
            hot_start, hot_end = (float(x) for x in args.hot.split(",", 1))
        except Exception:
            print("Invalid window format. Use 'start,end' in seconds.", file=sys.stderr)
            return 2

        baseline = Window(start_s=baseline_start, end_s=baseline_end)
        hot = Window(start_s=hot_start, end_s=hot_end)

    for label, window in [("baseline", baseline), ("hot", hot)]:
        if window.start_s < 0 or window.end_s <= window.start_s:
            print(f"Invalid {label} window: {window.start_s},{window.end_s}", file=sys.stderr)
            return 2
        if window.end_s > duration_s + 1e-6:
            print(
                f"{label} window exceeds duration ({window.end_s:.2f}s > {duration_s:.2f}s)",
                file=sys.stderr,
            )
            return 2

    out_dir = Path(args.output_dir).expanduser().resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    ts = time.strftime("%Y%m%d-%H%M%S")
    trace_path = out_dir / f"hush-hot-scene-memory-{ts}.trace"
    toc_xml = out_dir / f"hush-hot-scene-memory-{ts}.toc.xml"
    process_live_xml = out_dir / f"hush-hot-scene-memory-{ts}.process-live.xml"

    header_lines = [
        "== Hot Scene Pool Memory (xctrace) ==",
        f"- app: {app_exec}",
        f"- trace: {trace_path}",
        f"- duration: {duration_s:.1f}s",
        f"- baseline window: {baseline.start_s:.1f}-{baseline.end_s:.1f}s",
        f"- hot window: {hot.start_s:.1f}-{hot.end_s:.1f}s",
    ]
    if args.automation:
        header_lines.append("- mode: automation (scenario=hot-scene-memory)")
    if args.assert_range:
        header_lines.append(
            f"- expected delta: {args.expected_min_mib:.1f}-{args.expected_max_mib:.1f} MiB (assert)",
        )
    header_lines.append("")

    if args.automation:
        header_lines.extend(
            [
                "自动化说明：",
                "- App 会自动创建/填充会话并按时间表切换，形成 baseline/hot 两段稳态",
                "- 录制结束后脚本会自动导出 Activity Monitor 数据并计算内存 delta",
                "",
            ]
        )
    else:
        header_lines.extend(
            [
                "操作建议（在录制期间手动完成）：",
                "- 等待 baseline window 期间保持在一个会话（单 scene 稳态）",
                "- 随后切换/打开另外 2 个会话，使 hot scene pool 达到 3 个常驻（尽量包含 math/table 的 worst-case）",
                "- 在 hot window 期间保持稳定不操作",
                "",
            ]
        )

    print("\n".join(header_lines), file=sys.stderr)

    # Launch with a sanitized environment to avoid leaking unrelated secrets into the trace.
    minimal_env = {
        "HOME": os.environ.get("HOME", ""),
        "USER": os.environ.get("USER", ""),
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
        "TMPDIR": os.environ.get("TMPDIR", "/tmp"),
        "LANG": os.environ.get("LANG", "en_US.UTF-8"),
        # Ensure AppKit route + hot scene pool (AppKit route is default, but keep explicit).
        "HUSH_APPKIT_CONVERSATION": "1",
        "HUSH_HOT_SCENE_POOL": "1",
        # Reduce log noise during profiling.
        "HUSH_RENDER_DEBUG": "0",
        "HUSH_SWITCH_DEBUG": "0",
        "HUSH_CONTENT_DEBUG": "0",
    }

    if args.automation:
        minimal_env["HUSH_AUTOMATION_SCENARIO"] = "hot-scene-memory"
        minimal_env["HUSH_AUTOMATION_EXIT"] = "0"
        # Keep baseline long enough to cover the baseline window, then fill 3 scenes and hold.
        minimal_env["HUSH_AUTOMATION_BASELINE_HOLD_S"] = str(int(round(duration_s * 0.50)))
        minimal_env["HUSH_AUTOMATION_HOT_HOLD_S"] = str(int(round(duration_s * 0.70)))

        db_path_raw = (args.db_path or "").strip()
        if db_path_raw:
            db_path = Path(db_path_raw).expanduser().resolve()
        else:
            db_path = out_dir / f"hush-automation-{ts}.sqlite"
        db_path.parent.mkdir(parents=True, exist_ok=True)
        if db_path.exists():
            db_path.unlink()
        minimal_env["HUSH_DB_PATH"] = str(db_path)

    proc = subprocess.Popen([str(app_exec)], env=minimal_env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    pid = proc.pid
    print(f"launched pid={pid}", file=sys.stderr)
    duration_ms = int(round(float(args.duration_s) * 1000))

    try:
        _run(
            [
                "xcrun",
                "xctrace",
                "record",
                "--template",
                "Activity Monitor",
                "--time-limit",
                f"{duration_ms}ms",
                "--output",
                str(trace_path),
                "--no-prompt",
                "--attach",
                str(pid),
            ]
        )
    finally:
        if not args.keep_running:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()

    # Export TOC + the process-live table.
    _run(["xcrun", "xctrace", "export", "--input", str(trace_path), "--toc", "--output", str(toc_xml)])
    xpath = '/trace-toc/run[@number="1"]/data/table[@schema="activity-monitor-process-live"]'
    _run(
        [
            "xcrun",
            "xctrace",
            "export",
            "--input",
            str(trace_path),
            "--xpath",
            xpath,
            "--output",
            str(process_live_xml),
        ]
    )

    series = _parse_process_live_series(process_live_xml, mnemonic="memory-physical-footprint")
    if not series:
        print("No memory samples found in exported table.", file=sys.stderr)
        return 3

    effective_baseline = baseline
    effective_hot = hot
    if args.auto_windows:
        t0 = series[0][0]
        t1 = series[-1][0]
        span = max(0.0, t1 - t0)
        effective_baseline = Window(start_s=t0 + span * 0.20, end_s=t0 + span * 0.40)
        effective_hot = Window(start_s=t0 + span * 0.70, end_s=t0 + span * 0.90)

    baseline_vals = _select_window(series, effective_baseline)
    hot_vals = _select_window(series, effective_hot)
    if len(baseline_vals) < 1 or len(hot_vals) < 1:
        print(
            f"Not enough samples in windows (baseline={len(baseline_vals)}, hot={len(hot_vals)}). "
            "Try increasing --duration-s (or adjust --baseline/--hot when not using --auto-windows).",
            file=sys.stderr,
        )
        return 3

    baseline_mean = statistics.mean(baseline_vals)
    hot_mean = statistics.mean(hot_vals)
    delta = hot_mean - baseline_mean

    expected_min = float(args.expected_min_mib) * 1024 * 1024
    expected_max = float(args.expected_max_mib) * 1024 * 1024
    within_expected = expected_min <= delta <= expected_max

    print(
        "\n".join(
            [
                "",
                "== Result (memory-physical-footprint) ==",
                f"- samples: total={len(series)} baseline={len(baseline_vals)} hot={len(hot_vals)}",
                f"- series time span: {series[0][0]:.2f}-{series[-1][0]:.2f}s",
                f"- baseline window used: {effective_baseline.start_s:.2f}-{effective_baseline.end_s:.2f}s",
                f"- hot window used: {effective_hot.start_s:.2f}-{effective_hot.end_s:.2f}s",
                f"- baseline mean: {_fmt_mib(baseline_mean)}",
                f"- hot mean: {_fmt_mib(hot_mean)}",
                f"- delta (hot - baseline): {_fmt_mib(delta)}",
                "",
                f"- expected delta range: {args.expected_min_mib:.1f}-{args.expected_max_mib:.1f} MiB",
                (
                    f"- range check: {'PASS' if within_expected else 'FAIL'} (assert)"
                    if args.assert_range
                    else f"- range check: {'PASS' if within_expected else 'FAIL'} (informational)"
                ),
                f"- trace kept at: {trace_path}",
                f"- exports: {process_live_xml}",
            ]
        )
    )
    if args.assert_range and not within_expected:
        return 4
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
