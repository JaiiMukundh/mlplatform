#!/usr/bin/env bash
# Score one candidate version through the release gate in-cluster.
# Usage: VERSION=2 bash scripts/run_gate.sh
# Prints the gate verdict and leaves gate_report.json in the working directory.
# Exit 0 on PASS, 1 on REJECT (or Job failure).
set -Eeuo pipefail

readonly VERSION="${VERSION:?candidate VERSION required (e.g. VERSION=2)}"
readonly RENDERED="/tmp/gate-job.rendered.yaml"

sed -e "s/__CANDIDATE__/${VERSION}/" deploy/gate/gate-job.yaml >"${RENDERED}"
LOGS="$(mktemp)"
trap 'rm -f "${LOGS}"' EXIT
if JOB_TIMEOUT_SECONDS="${JOB_TIMEOUT_SECONDS:-900}" bash scripts/run_job.sh \
  "${RENDERED}" data >"${LOGS}" 2>&1; then
  GATE_STATUS=0
else
  GATE_STATUS=1
fi
cat "${LOGS}"
python3 - "${LOGS}" <<'EOF'
import re
import sys

logs = open(sys.argv[1]).read()
match = re.search(r"GATE verdict=(PASS|REJECT)", logs)
print(f"gate candidate verdict: {match.group(1) if match else 'UNKNOWN'}")
report = re.search(
    r"GATE_REPORT_BEGIN\n(\{.*?\n\})\nGATE_REPORT_END", logs, re.DOTALL
)
if report:
    open("gate_report.json", "w").write(report.group(1) + "\n")
    print("gate_report.json written")
EOF
exit "${GATE_STATUS}"
