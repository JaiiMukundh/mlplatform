# docs/runner-setup.md (P4.1 — HUMAN)

Install a self-hosted GitHub Actions runner on this laptop so `cd.yml` and
`model-release.yml` can deploy to the local kind cluster.

## Steps

1. Repo → Settings → Actions → Runners → New self-hosted runner → Linux x64.
   Copy the `config.sh` token URL.
2. Create the runner user workspace (as your normal user, NOT root):
   `mkdir -p ~/actions-runner && cd ~/actions-runner`
3. Download and configure (paste the commands GitHub shows):
   `curl -o actions-runner-linux-x64-*.tar.gz -L <url>`
   `tar xzf actions-runner-linux-x64-*.tar.gz`
   `./config.sh --url https://github.com/<OWNER>/<REPO> --token <TOKEN> --labels mlp-local --name mlp-laptop --work _work`
4. Install as a service so it survives reboots:
   `sudo ./svc.sh install && sudo ./svc.sh start`
   Verify: `sudo ./svc.sh status` shows running.
5. Give the runner Docker access (same requirement as your shell):
   `sudo usermod -aG docker "$USER"` then log out/in, or run the service
   as a user already in the `docker` group. Verify on the laptop:
   `docker info` shows the server and `kind get clusters` lists `mlp`.
6. Repo → Settings → Secrets → Actions → New repository secret:
   name `GITHUB_DISPATCH_TOKEN`, value a classic PAT with `repo` scope
   (used by the retrain service to fire `model-candidate-ready`, P8.4).
   Add to `.env` locally as well (never commit `.env`).
7. Verify end to end: push a trivial commit to `main`; the `cd` workflow
   should queue on the runner, build, scan, push, deploy staging+serving,
   and smoke. Check Actions → cd → green.

## Gotchas

- The runner needs `tofu`, `helm`, `kubectl`, `kind`, `docker`, `uv`,
  `ruff`, `mc` on PATH (same as `make bootstrap` prerequisites).
- Keep the laptop awake and on the same network during deploys.
- If no jobs pick up, check labels are exactly `[self-hosted, mlp-local]`
  and the service is running.
