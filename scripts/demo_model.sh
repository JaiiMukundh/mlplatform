#!/usr/bin/env bash
# End-to-end drift self-healing demo (P8.7): reset -> baseline traffic ->
# simulate drift -> drifted traffic -> watch the loop close itself.
# Expected timeline (production monitor settings: 60s interval, 2 consecutive):
#   t0   baseline traffic: model_drift_detected=0, PSI < 0.1
#   t1   simulate_drift --scenario both; drifted traffic
#   t1+~3m model_drift_detected=1 (>=2 features PSI>0.25), ModelDriftDetected fires
#   +~1m retrain Job runs -> MLflow version alias candidate
#   +~8m release (gate PASS, staging PASS, prod rollout)
#   +~2m /model-info == new version on all pods; PSI back < 0.1; flag 0
# No human action between t1 and the end. Exits non-zero on timeout (40 min).
set -Eeuo pipefail

stamp() { date -u +%FT%TZ; }
mlflow_versions() {
  curl -s "localhost:5000/api/2.0/mlflow/model-versions/search?filter=name%3D%27loan-default%27" |
    python3 -c "import json,sys; print(sorted(v['version'] for v in json.load(sys.stdin).get('model_versions',[])))"
}
prod_version() { curl -s localhost:8080/model-info | python3 -c "import json,sys; print(json.load(sys.stdin)['version'])"; }
drift_flag() {
  curl -s "localhost:9090/api/v1/query?query=max(model_drift_detected)" |
    python3 -c "import json,sys; r=json.load(sys.stdin)['data']['result']; print(r[0]['value'][1] if r else '?')"
}
monitor_state() { curl -s localhost:8089/state; }
candidate_version() {
  curl -s "localhost:5000/api/2.0/mlflow/registered-models/get?name=loan-default" |
    python3 -c "import json,sys; a=json.load(sys.stdin)['registered_model'].get('aliases', []); print(next((x['version'] for x in a if x['alias']=='candidate'), '-'))"
}

echo "[$(stamp)] t0: reset to baseline"
uv run python scripts/reset_demo.py

kubectl -n observability port-forward deploy/drift-monitor 8089:8080 \
  >/tmp/demo-drift-pf.log 2>&1 &
PF_PID=$!
trap 'kill ${TRAFFIC_PID:-} ${PF_PID:-} 2>/dev/null || true' EXIT
sleep 4

echo "[$(stamp)] t0: baseline traffic (2 min)"
uv run python scripts/traffic.py --rps 20 --duration 120 --url http://localhost:8080
echo "[$(stamp)] baseline state: $(monitor_state | head -c 300)"

echo "[$(stamp)] t1: simulate drift (both)"
START_VERSION="$(prod_version)"
echo "[$(stamp)] prod version before drift: ${START_VERSION}"
uv run python scripts/simulate_drift.py --scenario both

echo "[$(stamp)] t1: drifted traffic in background"
uv run python scripts/traffic.py --rps 30 --duration 1500 --url http://localhost:8080 \
  >/tmp/demo-traffic.log 2>&1 &
TRAFFIC_PID=$!
sleep 4

deadline=$((SECONDS + 2400))
BEFORE_VERSIONS="$(mlflow_versions)"
saw_drift=0
saw_job=0
while ((SECONDS < deadline)); do
  state="$(monitor_state)"
  flag="$(drift_flag)"
  jobs="$(kubectl -n data get jobs -l app=retrain -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)"
  candidate="$(candidate_version)"
  versions="$(mlflow_versions)"
  prod="$(prod_version)"
  echo "[$(stamp)] flag=${flag} jobs='${jobs}' candidate=${candidate} versions=${versions} prod=${prod}"
  echo "  state: $(echo "${state}" | head -c 220)"
  if [[ "${flag}" == "1" ]]; then saw_drift=1; fi
  if [[ -n "${jobs}" ]]; then saw_job=1; fi
  if [[ "${saw_drift}" == 1 && "${saw_job}" == 1 && "${versions}" != "${BEFORE_VERSIONS}" && "${prod}" != "${START_VERSION}" && "${flag}" == "0" ]]; then
    echo "[$(stamp)] LOOP CLOSED: prod ${START_VERSION} -> ${prod}, drift flag clear"
    kill "${TRAFFIC_PID}" "${PF_PID}" 2>/dev/null || true
    exit 0
  fi
  sleep 45
done
echo "[$(stamp)] TIMEOUT waiting for the loop to close"
exit 1
