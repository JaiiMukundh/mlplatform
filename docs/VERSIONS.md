# Exact version references

The authoritative Python pins are in `uv.lock` and `core/requirements/*.txt`; container base pins are in `infra/Dockerfile`; Terraform providers are in `infra/envs/azure/.terraform.lock.hcl`; GitHub Actions use commit SHAs in `.github/workflows/`. Update this list when changing a pin, after checking the official stable release source.

| Component | Pin in current cloud path |
|---|---|
| Python image | `python:3.11.17-slim-trixie@sha256:e88e9763f943ec1834f992a4b51e0f24500486803e8bc534e5767af9ea65f6ce` |
| Azure provider | `hashicorp/azurerm 5.9.0` |
| Kubernetes provider | `hashicorp/kubernetes 3.4.0` |
| Random provider | `hashicorp/random 3.9.1` |
| TLS provider | `hashicorp/tls 4.4.1` |
| GitHub Terraform CLI | `1.16.5` |
| GitHub uv | `0.13.0` |
| AKS kubectl | `1.37.1` |
| Prometheus stack manifest snapshot | `91.8.2` |
| Loki manifest snapshot | `7.3.0` |
| Alloy manifest snapshot | `1.13.0` |
| MLflow | `3.16.1` |
| Feast | `0.66.0` |
| scikit-learn | `1.9.1` |
| PostgreSQL image | `postgres:16.15-bookworm@sha256:efedf3595f1d6f415c08568ba171029bf54052e754cc9f030e3f2412b21f3d67` |
| MinIO image | `bitnamilegacy/minio:2025.7.23-debian-12-r3@sha256:953d489a81cc4de7975f90e07202189c4325da39b0b92470b6a13c7ea99e36cd` |
| Redis image | `redis:7.2.16-alpine3.21@sha256:29e8589c3f9ba699b5f7aa4b3c7733c58852a3626439e619aa0ee78de08c6ca0` |
| gitleaks | `8.30.1` |
| actionlint | `1.7.12` |
| hadolint | `2.15.1` |
| kubeconform | `0.8.0` |
| trivy | `0.75.0` |

The exact AKS patch version is supplied through `AZURE_KUBERNETES_VERSION` for the chosen region. The AKS provider pins were checked against the official Terraform Registry on 2026-10-21: [Kubernetes](https://registry.terraform.io/providers/hashicorp/kubernetes/latest), [Random](https://registry.terraform.io/providers/hashicorp/random/latest), and [TLS](https://registry.terraform.io/providers/hashicorp/tls/latest). The AKS manifest snapshot keeps the pinned observability versions above.
