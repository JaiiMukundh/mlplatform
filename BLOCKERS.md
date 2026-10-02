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
