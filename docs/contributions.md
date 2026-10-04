# Student Contribution Statement & Ownership Matrix (P10.4)

This document outlines the division of responsibilities, component ownership, and individual technical contributions of the student engineering team for the Autonomous Self-Healing Machine Learning Platform.

---

## 1. Team Roster & Ownership Summary

| Student Name | Student ID | Primary Engineering Domain | Primary Modules / Components |
|---|---|---|---|
| **[Student 1 Name]** | `[Student 1 ID]` | Infrastructure, IaC, Orchestration & Resilience | OpenTofu (`infra/`), Kind Cluster, Helm Charts, HPA, Remediator (`remediator/`), Chaos Testing (`scripts/chaos_*`) |
| **[Student 2 Name]** | `[Student 2 ID]` | Serving Engine, Feature Store & Model Registry | FastAPI Serving (`model_api/`), Feast Online/Offline (`feast_repo/`), MLflow Registry (`ml/`), Redis, PostgreSQL |
| **[Student 3 Name]** | `[Student 3 ID]` | Statistical Monitoring, Closed-Loop Retrain & CI/CD | Drift Detection (`drift_monitor/`), Retraining Engine (`retrain/`), Quality Gates (`gate.py`), GitHub Actions CI/CD |

---

## 2. Detailed Student Contribution Breakdowns

### 2.1 Student 1: Infrastructure as Code & Operational Resilience
* **Lead Responsibilities:**
  * Architecture and composition of the 3-node Kind Kubernetes cluster with local container registry (`localhost:5001`).
  * OpenTofu modules for local environment (`infra/envs/local`) and AWS cloud parity (`infra/envs/aws`: EKS, RDS, S3, ECR, IAM/IRSA).
  * Implementation of Kubernetes Pod Disruption Budgets (PDB), Horizontal Pod Autoscaling (HPA), and topology spread constraints.
  * Development of the automated incident `remediator` service and Alertmanager webhook integration.
  * Fault injection and chaos testing scripts (`chaos_pod.sh`, `chaos_alert.sh`, `verify_failure_modes.sh`).
* **Key Git Commits & PRs:**
  * `[Hash / Link]`: Implement Kind and local registry OpenTofu modules (P3.1, P3.2).
  * `[Hash / Link]`: Deploy Prometheus stack, Loki, Alloy, and configure alert manager routing (P5.1, P5.2).
  * `[Hash / Link]`: Build remediator webhook and verify automated HPA scaling response (P5.6, P5.7).
  * `[Hash / Link]`: AWS parity infrastructure modules and cost guardrails (P3.6, P9.5).
* **Viva Defense Specialization:**
  * Kubernetes reconciliation loops and failure semantics.
  * OpenTofu state management and zero-cost local vs cloud architecture parity.
  * Automated remediation safety mechanisms (debouncing, cooldowns, role-based access).

---

### 2.2 Student 2: Model Serving, Feature Parity & Registry Management
* **Lead Responsibilities:**
  * Production inference microservice (`model_api`) with FastAPI, Uvicorn, and Pydantic validation.
  * Decoupling model artifacts and training datasets from container images (zero data in Docker).
  * Centralized Feature Store (Feast) architecture: Redis online store hydration ($<2$ms) and MinIO Parquet offline store.
  * Proving mathematical and empirical training-serving feature parity (`tests/test_parity.py`).
  * Asynchronous, in-memory buffered prediction logging (`PredictionLogger`) with batch PostgreSQL flushes.
  * MLflow model registry integration, metadata tracking, and model version pinning in Helm.
* **Key Git Commits & PRs:**
  * `[Hash / Link]`: Implement model-api with async logging and provider protocols (P1.3, P1.4).
  * `[Hash / Link]`: Set up Feast repository, entities, and feature views (P6.2, P6.3).
  * `[Hash / Link]`: Establish MLflow tracking, run artifacts, and training-serving feature parity test (P6.4, P6.4b).
  * `[Hash / Link]`: Transition serving to Feast/MLflow providers and verify immutable version deploys (P6.5, P6.7).
* **Viva Defense Specialization:**
  * Why Feast point-in-time joins eliminate future data leakage during training.
  * Why in-memory decoupled prediction buffering prevents database outages from affecting user inference.
  * Rationale for immutable model version pinning over dynamic alias resolution.

---

### 2.3 Student 3: Statistical Drift Detection, Retraining Loop & CI/CD
* **Lead Responsibilities:**
  * Statistical drift engine implementing Population Stability Index (PSI) and Kolmogorov-Smirnov (KS) tests.
  * Autonomous `drift-monitor` daemon with multi-breach debouncing, cooldown timers, and active-job locking.
  * Ephemeral Kubernetes batch Retrain Job generating candidate LightGBM models.
  * Rigorous candidate quality release gates (`scripts/gate.py`): AUC floor, non-regression checks, schema validation.
  * Continuous Integration (`ci.yml`) and Continuous Deployment (`cd.yml`, `model-release.yml`) workflows.
  * Repeatable end-to-end drift simulation and self-healing demonstration (`make demo-model`).
* **Key Git Commits & PRs:**
  * `[Hash / Link]`: Formulate and unit test statistical drift math for PSI and KS (P8.1).
  * `[Hash / Link]`: Build drift-monitor service and Kubernetes Retrain Job spawner (P8.2, P8.3, P8.4).
  * `[Hash / Link]`: Implement model quality gate and 2,000-request staging load check (P7.1, P7.2).
  * `[Hash / Link]`: Create end-to-end drift demo orchestration and demo reset suite (P8.7, P8.8, P9.1).
* **Viva Defense Specialization:**
  * Mathematical justification of PSI vs KS test for categorical vs continuous drift.
  * Mitigation of retraining loops and model flapping via MLflow run-tied reference distributions.
  * Unified release pipeline design for both software code and machine learning models.

---

## 3. Team Collaboration & Git Hygiene

* **Mono-Repository Structure:** Single repository encompassing IaC, Kubernetes configurations, microservice code, and ML models.
* **Commit Standards:** Conventional Commits (`feat:`, `fix:`, `docs:`, `test:`, `infra:`, `chore:`).
* **Branching Strategy:** Short-lived feature branches (`feat/...`, `fix/...`) merged to `main` via Pull Requests with mandatory CI checks (ruff, pytest, tofu validate, hadolint, gitleaks).
* **Pair Programming & Knowledge Transfer:** Regular cross-functional code reviews ensuring all three team members can operate, demo, and defend any part of the platform.

---

## 4. Verification Sign-Off

*(To be signed by students prior to academic viva submission)*

* Student 1: ___________________________ Date: ____________
* Student 2: ___________________________ Date: ____________
* Student 3: ___________________________ Date: ____________
