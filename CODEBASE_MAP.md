# 🗺️ Codebase Map & Survival Guide: The 3 Buckets

> **Rule of Thumb for Presentations & Vivas:**  
> In production MLOps, 80% of any repository is infrastructure scaffolding (Dockerfiles, Helm charts, Terraform templates).  
> **You do NOT need to explain every file.** If an evaluator asks about the codebase, walk them through the **3 Buckets** and open **only the 5 core files**.

---

## 🏛️ The 3 Buckets Architecture

```
mlplatform/
│
├── 🧠 BUCKET 1: THE CORE ML & SERVING LOGIC (What Actually Does the Work)
│   ├── model_api/        ──> FastAPI sub-15ms prediction service
│   ├── drift_monitor/    ──> Background watchdog evaluating PSI drift
│   ├── ml/               ──> Offline training & LightGBM model pipeline
│   ├── mlp_common/       ──> Shared statistical math (PSI formula) & schemas
│   ├── retrain/          ──> In-cluster autonomous retraining orchestrator
│   ├── remediator/       ──> Auto-healing controller for infra latency
│   └── feature_repo/     ──> Feast feature definitions (Redis + MinIO)
│
├── 🏗️ BUCKET 2: INFRASTRUCTURE & PACKAGING (The Cloud Plumbing)
│   ├── docker/           ──> 6 multi-stage Dockerfiles (one per microservice)
│   ├── deploy/           ──> Kubernetes manifests & Helm charts (Redis, Postgres, MLflow)
│   └── infra/            ──> OpenTofu / Kind IaC (cluster provisioning)
│
└── 🛠️ BUCKET 3: OPERATIONS & INTERFACE (How We Run & Demo It)
    ├── ui/               ──> Central Cypherpunk Control Plane (localhost:8050)
    ├── scripts/          ──> Active operational scripts (traffic, chaos, drift)
    │   └── archive/      ──> Historical one-off test scripts
    └── docs/             ──> Plain-English guide, architecture diagram & runbook
        └── archive/      ──> Internal design notes & old sprint trackers
```

---

## 📖 The 1-Sentence Directory Dictionary

If an evaluator points to *any* folder in your sidebar, here is your 1-sentence answer:

| Directory | What to Say |
| :--- | :--- |
| **`model_api/`** | *"Our production FastAPI inference microservice that fetches features from Redis and serves sub-15ms predictions."* |
| **`drift_monitor/`** | *"The continuous watchdog daemon that queries PostgreSQL and calculates drift every 10 seconds."* |
| **`ml/`** | *"The machine learning pipeline that trains LightGBM on Feast historical features and logs runs to MLflow."* |
| **`mlp_common/`** | *"Our shared internal Python library containing the Population Stability Index (PSI) algorithm and Pydantic schemas."* |
| **`retrain/`** | *"The in-cluster Kubernetes job that retrains fresh candidate models when drift breaches 0.25 PSI."* |
| **`remediator/`** | *"Our infrastructure self-healing daemon that listens to Alertmanager webhooks and dynamically scales pod minimums."* |
| **`feature_repo/`** | *"Our Feast feature store repo defining offline S3 parquet files and online Redis feature views."* |
| **`deploy/`** | *"Production Helm charts that declare how each service runs in Kubernetes with resource limits and health checks."* |
| **`docker/`** | *"Hardened, non-root, multi-stage Dockerfiles for building minimal, reproducible container images."* |
| **`infra/`** | *"Infrastructure-as-Code (OpenTofu) that provisions our 3-node Kind Kubernetes cluster and networks."* |
| **`scripts/`** | *"Day-2 operational automation scripts for traffic generation, drift simulation, and disaster reset."* |
| **`ui/`** | *"Our central operations dashboard allowing visual inspection of live PSI, pod health, and borrower scoring."* |
| **`docs/`** | *"Complete documentation including the plain-English architecture guide, viva prep, and runbooks."* |

---

## 🎯 The Only 5 Files You Need to Open in a Demo

Whenever asked to show code, **never wander through config files**. Open these exact 5 files:

### 1. `model_api/main.py` (Serving & Async Logging)
* **What to show:** Lines 149–185 (`@application.post("/predict")`).
* **What to explain:** 
  > *"When an applicant submits their ID, we look up their 23 features in Redis in 1ms, pass them to our cached Champion model, and write an immutable record to PostgreSQL in an async background worker so the customer never waits."*

### 2. `mlp_common/drift.py` (Statistical Math)
* **What to show:** Lines 25–65 (`calculate_psi()`).
* **What to explain:** 
  > *"This is our mathematical engine. It divides live prediction distributions into reference quantiles, adds Laplace smoothing to prevent division by zero, and computes the Kullback-Leibler symmetric divergence (PSI)."*

### 3. `drift_monitor/main.py` (The 5 Safeguards)
* **What to show:** Lines 60–95 (`evaluate_drift()`).
* **What to explain:** 
  > *"Here is our continuous surveillance loop. It enforces our 5 safeguards: requires ≥100 samples, checks for ≥2 drifted features, debounces for 2 consecutive cycles, checks job locks, and honors a 30s cooldown before alerting Kubernetes."*

### 4. `ml/train.py` (Feast Point-in-Time Training)
* **What to show:** Lines 70–110 (`train_candidate()`).
* **What to explain:** 
  > *"When retraining triggers, this script pulls point-in-time correct customer feature vectors from Feast/MinIO, trains a fresh LightGBM classifier, records validation metrics, and uploads the candidate artifact to MLflow."*

### 5. `scripts/gate.py` (The 5-Stage Automated Quality Bouncer)
* **What to show:** Lines 85–130 (`evaluate_gate()`).
* **What to explain:** 
  > *"Before any candidate model touches customer traffic, our automated gate tests it: AUC must exceed 0.70, positive rate must be sane, schema must match 23 features, and it must not regress against the current champion."*

---

## 🎤 3-Minute Elevator Pitch Script (Memorize This!)

If an examiner says: *"Give me an overview of what you built,"* use this exact structure:

1. **The Problem (30s):**
   > *"In production ML, models silently rot due to Data Drift—the real world changes, but the code has zero bugs. In our case, macroeconomic shifts cause credit delinquency to surge, causing our old model to 'slur' and wrongfully reject super-prime borrowers."*

2. **The 3 Buckets Architecture (60s):**
   > *"We built an autonomous self-healing platform organized in 3 buckets:*  
   > *1. **Core ML Logic:** A sub-15ms FastAPI service backed by Redis and PostgreSQL.*  
   > *2. **Autonomous Watchdog:** A drift-monitor calculating PSI every 10s. When PSI > 0.25 across 2 features, it spawns an in-cluster training job without human intervention.*  
   > *3. **Cloud Infrastructure:** Kubernetes (Kind) managing rolling updates, quality gates, and automated canary tests so models deploy with zero downtime."*

3. **The Proof (30s):**
   > *"We can simulate a macroeconomic shock right now. You'll see applicant #7 flip from Approved to Rejected, our watchdog catch the breach, retrain Candidate v64, pass all 5 safety gates, and restore applicant #7 to Approved—all while surviving pods handle 100% of live traffic with zero dropped requests."*
