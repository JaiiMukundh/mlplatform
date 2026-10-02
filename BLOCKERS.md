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
- Status: active; P1.7 remains unchecked.
