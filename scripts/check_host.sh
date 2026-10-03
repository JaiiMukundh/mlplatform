#!/usr/bin/env bash
# Host preflight: verify the kernel limits that kind's multi-node clusters need.
#
# A 3-node kind cluster exhausts the default inotify budget. When that happens
# kube-proxy dies with "fsnotify watcher init: too many open files", CoreDNS can
# no longer reach the API server VIP, and every in-cluster DNS lookup fails, so
# all podified services (MLflow, Feast, model-api) crash. Failing here keeps us
# from ever building that silently broken cluster. See BLOCKERS.md BLK-002/BLK-004.
set -Eeuo pipefail

readonly REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REQUIRED_INSTANCES=512
readonly REQUIRED_WATCHES=524288

read_proc_value() {
  # Read a sysctl straight from /proc so this works without sysctl(8).
  local key="$1"
  local path="/proc/sys/${key//.//}"
  if [[ -r "${path}" ]]; then
    tr -d '[:space:]' <"${path}"
  fi
}

failures=()

check_minimum() {
  local key="$1"
  local required="$2"
  local observed="$3"

  if [[ -z "${observed}" ]]; then
    printf 'unknown %-32s (required >= %s)\n' "${key}" "${required}"
    failures+=("${key}")
  elif ((observed >= required)); then
    printf 'ok      %-32s %s (required >= %s)\n' "${key}" "${observed}" "${required}"
  else
    printf 'too low %-32s %s (required >= %s)\n' "${key}" "${observed}" "${required}"
    failures+=("${key}")
  fi
}

printf 'MLPlatform host preflight\n'
check_minimum fs.inotify.max_user_instances \
  "${REQUIRED_INSTANCES}" \
  "$(read_proc_value fs.inotify.max_user_instances)"
check_minimum fs.inotify.max_user_watches \
  "${REQUIRED_WATCHES}" \
  "$(read_proc_value fs.inotify.max_user_watches)"

if ((${#failures[@]} > 0)); then
  cat >&2 <<EOF

The kernel inotify limits above are too low for a 3-node kind cluster
(exhausted limits break kube-proxy and CoreDNS; see BLOCKERS.md BLK-002/BLK-004).

Apply the fix now (requires root):
  sudo sysctl -w fs.inotify.max_user_instances=${REQUIRED_INSTANCES}
  sudo sysctl -w fs.inotify.max_user_watches=${REQUIRED_WATCHES}

Make it survive reboots (recommended, one time):
  sudo install -m 0644 ${REPO_ROOT}/infra/sysctl/99-kind-inotify.conf \\
    /etc/sysctl.d/99-kind-inotify.conf
  sudo sysctl --system

Then rerun \`make preflight\`.
EOF
  exit 1
fi

printf '\nKernel limits satisfy the kind requirements.\n'