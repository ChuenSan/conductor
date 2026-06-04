#!/usr/bin/env bash
# Validate the diagnostics performance report from an exported bundle.
#
# Usage:
#   ./Scripts/performance-gate.sh /path/to/summary.redacted.json
set -euo pipefail

SUMMARY_PATH="${1:-}"
if [[ -z "$SUMMARY_PATH" || ! -s "$SUMMARY_PATH" ]]; then
  echo "performance-gate.sh: expected a diagnostics summary JSON path" >&2
  exit 1
fi

REQUIRED_BUDGETS="${CONDUCTOR_PERF_GATE_REQUIRED_BUDGETS:-workspace.switch,terminal.tab-switch,terminal.scroll-frame,browser.restore,settings.open,command-palette.open}"
MIN_SAMPLED_BUDGETS="${CONDUCTOR_PERF_GATE_MIN_SAMPLED_BUDGETS:-5}"
MIN_RECENT_SAMPLES="${CONDUCTOR_PERF_GATE_MIN_RECENT_SAMPLES:-5}"
MAX_OVER_BUDGET="${CONDUCTOR_PERF_GATE_MAX_OVER_BUDGET:-0}"
ENFORCED_BUDGETS="${CONDUCTOR_PERF_GATE_ENFORCED_BUDGETS:-$REQUIRED_BUDGETS}"

python3 - "$SUMMARY_PATH" "$REQUIRED_BUDGETS" "$MIN_SAMPLED_BUDGETS" "$MIN_RECENT_SAMPLES" "$MAX_OVER_BUDGET" "$ENFORCED_BUDGETS" <<'PY'
import json
import sys

summary_path, required_raw, min_sampled_raw, min_recent_raw, max_over_raw, enforced_raw = sys.argv[1:7]
required = {item.strip() for item in required_raw.split(",") if item.strip()}
enforced = {item.strip() for item in enforced_raw.split(",") if item.strip()}

try:
    min_sampled = int(min_sampled_raw)
    min_recent = int(min_recent_raw)
    max_over = int(max_over_raw)
except ValueError as error:
    raise SystemExit(f"performance-gate.sh: invalid numeric threshold: {error}") from error

with open(summary_path, "r", encoding="utf-8") as handle:
    summary = json.load(handle)

performance = summary.get("performance") or {}
report = performance.get("report") or {}
budgets = ((performance.get("budgets") or {}).get("items") or [])
recent_samples = ((performance.get("samples") or {}).get("recent") or [])

if not report:
    raise SystemExit("performance-gate.sh: diagnostics summary is missing performance.report")

sampled_budget_ids = {
    item.get("id")
    for item in budgets
    if item.get("id") and item.get("status") != "not_sampled" and item.get("lastSample") is not None
}
missing_required = sorted(required - sampled_budget_ids)
if missing_required:
    raise SystemExit(
        "performance-gate.sh: missing required sampled budgets: "
        + ", ".join(missing_required)
    )

sampled_budget_count = int(report.get("sampledBudgetCount") or len(sampled_budget_ids))
recent_sample_count = int(report.get("recentSampleCount") or len(recent_samples))
if sampled_budget_count < min_sampled:
    raise SystemExit(
        f"performance-gate.sh: sampledBudgetCount {sampled_budget_count} < {min_sampled}"
    )
if recent_sample_count < min_recent:
    raise SystemExit(
        f"performance-gate.sh: recentSampleCount {recent_sample_count} < {min_recent}"
    )

over_budget_samples = report.get("recentOverBudgetSamples") or []
enforced_over_budget_samples = [
    sample for sample in over_budget_samples
    if sample.get("budgetID") in enforced
]
over_budget_count = len(enforced_over_budget_samples)
if over_budget_count > max_over:
    details = ", ".join(
        f"{sample.get('budgetID', '<unknown>')}={sample.get('durationMS', '?')}ms>{sample.get('targetMS', '?')}ms"
        for sample in enforced_over_budget_samples[:8]
    )
    raise SystemExit(
        f"performance-gate.sh: recentOverBudgetCount {over_budget_count} > {max_over}"
        + (f" ({details})" if details else "")
    )

missing_budget_ids = report.get("missingBudgetIDs") or []
print(
    "performance_gate=ok "
    f"status={report.get('status', '<missing>')} "
    f"sampledBudgets={sampled_budget_count} "
    f"recentSamples={recent_sample_count} "
    f"overBudget={over_budget_count} "
    f"ignoredOverBudget={len(over_budget_samples) - over_budget_count} "
    f"missingBudgets={len(missing_budget_ids)}"
)
PY
