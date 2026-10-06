# Blockers

## BLK-001 — Docker daemon cannot start without `newuidmap`

- First observed: 2026-10-02 during P1.7.
- Impact: container build/run and all kind/Kubernetes runtime acceptance checks.
- Evidence: the installed Docker 29.8.2 CLI cannot find `/var/run/docker.sock`.
  Official rootless Docker setup was attempted with host networking and then with
  pinned `slirp4netns` 1.3.5; the latter reached RootlessKit and failed with
  `failed to setup UID/GID map: exec: "newuidmap": executable file not found`.
- Cause: `/etc/subuid` and `/etc/subgid` are configured, but Linux Mint's privileged
  `uidmap` package is absent. This process cannot use interactive `sudo`.
- Human unblock (minimal): run `sudo apt update && sudo apt install -y uidmap`, then
  tell the agent to continue. Rootless Docker setup and validation can then resume.
- Resolved: 2026-10-02. The `uidmap` package is now installed (`/usr/bin/newuidmap`
  present) and the rootless Docker daemon is active (`docker info` reports
  `Context: rootless`). `make build` now completes.
- Residual note: the default bridge has no working DNS resolution (even public resolvers
  fail from the container netns), so the image build uses host networking
  (`DOCKER_BUILD_NETWORK=host`). Recorded in `docs/DECISIONS.md`.
- Status: closed.

## BLK-002 — kind worker cannot join: host inotify limits too low

- First observed: 2026-10-02 during P2.2.
- Impact: a 3-node kind cluster only brings up two Ready nodes; the second worker's
  kubelet and kube-proxy cannot start. P2.2's "3 Ready nodes" acceptance cannot pass.
- Evidence: `docker exec mlp-worker2 journalctl -u kubelet` shows
  `E1002 ... "Failed to start cAdvisor" err="inotify_init: too many open files"` and
  `kubelet.service: Main process exited, code=exited, status=1/FAILURE`. The host reports
  `fs.inotify.max_user_instances = 128`.
- Cause: three node containers exhaust the default per-user inotify instance limit;
  kind documents `fs.inotify.max_user_instances >= 512`. Raising it requires root.
- Human unblock (minimal):
  `sudo sysctl -w fs.inotify.max_user_instances=512`
  `sudo sysctl -w fs.inotify.max_user_watches=524288`
  (persist via `/etc/sysctl.d/99-kind.conf`), then:
  `kind delete cluster --name mlp`
  `kind create cluster --name mlp --config infra/kind-config.yaml`
BLK-002's inotify limits were raised by the human (`fs.inotify.max_user_instances=512`,
`fs.inotify.max_user_watches=524288`) and confirmed via `/proc/sys/fs/inotify/*`.
- Status: resolved.

## BLK-003 — Rootful Docker Engine is not installed

- First observed: 2026-10-02.
- Impact: the project targets the standard Docker daemon
  (`unix:///var/run/docker.sock`); image builds (`make build`) and the kind cluster must run
  there. Only the rootless extras are currently installed.
- Evidence: `/var/run/docker.sock` does not exist; `systemctl is-enabled docker` returns
  `not-found`; no `docker-ce`/`docker.io` package is installed; `dockerd`, `docker`, and
  `containerd` exist only under `~/.local/bin`; `sudo` requires a password, so the agent
  cannot install or start the daemon.
- Human unblock (Debian/Ubuntu/Mint):
  `sudo apt-get update && sudo apt-get install -y docker.io`
  `sudo systemctl enable --now docker`
  `sudo usermod -aG docker "$USER"`        # then log out and back in (or: newgrp docker)
  `sudo sysctl -w fs.inotify.max_user_instances=512`
  `sudo sysctl -w fs.inotify.max_user_watches=524288`
  `docker context use default`
- Verify: `docker info` shows the server; `make build` succeeds; then
  `kind create cluster --name mlp --config infra/kind-config.yaml` and `kubectl get nodes`.
- **Status update (2026-10-02):** the rootful Docker Engine is now installed
  (`docker.io`, server 29.1.3) and this user is a member of the `docker` group
  (`getent group docker` lists the user; works now via `sg docker`, and directly
  after a fresh login for the group membership to take effect).
- Status: resolved.

## BLK-004 — BLK-002 recurrence: reboot reset the inotify limits, cluster DNS down

- First observed: 2026-10-03 (P6, after the host rebooted ~5h earlier).
- Impact: the whole cluster loses service networking. NodePorts from the host
  reset the connection, and every in-cluster DNS lookup fails, so all podified
  services crash-loop (MLflow `Temporary failure in name resolution`, CoreDNS
  0/1, metrics-server / kube-state-metrics / loki-gateway CrashLoopBackOff,
  model-api `Unknown`). No P6 acceptance check can run.
- Evidence:
  - `cat /proc/sys/fs/inotify/max_user_instances` -> `128` (the kernel default;
    `max_user_watches` -> `248131`).
  - `kubectl logs -n kube-system kube-proxy-bqwww` ->
    `err="failed complete: fsnotify watcher init: too many open files"`.
  - `kubectl logs -n kube-system deploy/coredns` ->
    `Failed to watch ... dial tcp 10.96.0.1:443: i/o timeout` and
    `Plugins not ready: "kubernetes"`.
  - `kubectl logs -n data deploy/mlflow` ->
    `failed to resolve host 'postgres.data.svc': [Errno -3] Temporary failure in name resolution`.
  - `curl localhost:9090/-/ready`, `localhost:9000/minio/health/live`,
    `localhost:5000/health` -> all `Recv failure: Connection reset by peer`.
  - `kubectl get nodes` still shows all three nodes `Ready` (kubelet survived),
    which is why this presents as a networking outage rather than a node outage.
- Cause: BLK-002 was fixed with `sysctl -w` (runtime only). Nothing wrote the
  values to `/etc/sysctl.d/`, so the reboot reverted the host to the default
  128 inotify instances -- below the 512 kind documents for 3 nodes.
- Human unblock (requires root; the agent has no passwordless sudo):
  `sudo sysctl -w fs.inotify.max_user_instances=512`
  `sudo sysctl -w fs.inotify.max_user_watches=524288`
  then make it permanent:
  `sudo install -m 0644 infra/sysctl/99-kind-inotify.conf /etc/sysctl.d/99-kind-inotify.conf`
  `sudo sysctl --system`
  then let the broken pods recover:
  `kubectl delete pod -n kube-system -l k8s-app=kube-dns`
  `kubectl delete pod -n kube-system -l k8s-app=kube-proxy`
- Agent-side guard added while blocked: `scripts/check_host.sh` (target
  `make preflight`, also the first step of `make up`) and the persistent drop-in
  `infra/sysctl/99-kind-inotify.conf`, both recorded in `docs/DECISIONS.md`.
- Status: **resolved 2026-10-03.** The human applied `fs.inotify.max_user_instances=512`
  and `fs.inotify.max_user_watches=524288` and installed `infra/sysctl/99-kind-inotify.conf`
  into `/etc/sysctl.d/` (so it now survives reboots). kube-proxy and CoreDNS were
  recycled and recovered; `kubectl exec -n data postgres-0 -- getent hosts minio.data.svc`
  now resolves (`10.96.47.48`), the crash-looped pods were rolled, and MLflow is `1/1`.
  `make preflight` reports `ok ... 512 (required >= 512)`.
