# Git workflow

`main` is the releasable branch and is protected by convention until repository-side
branch protection is configured. Direct feature development uses short-lived branches
named `feat/<phase>-<topic>`, for example `feat/p1-model-api`.

Every commit follows Conventional Commits (`feat:`, `fix:`, `test:`, `build:`,
`docs:`, `chore:`). A task is committed only after its acceptance check is observed,
its box is checked in `TASKS.md`, and a concise real-output summary is appended to
`PROGRESS.md`.

Pull requests use the repository template. CI must pass before merge; P4 will enforce
this remotely once the private GitHub repository and runner are connected.
