"""Generates docs/architecture.png architecture diagram."""
from PIL import Image, ImageDraw, ImageFont
import os

def create_diagram():
    width = 1200
    height = 700
    img = Image.new("RGB", (width, height), color="#1e1e2e")
    draw = ImageDraw.Draw(img)

    # Colors
    c_card = "#282a36"
    c_border = "#6272a4"
    c_header = "#bd93f9"
    c_text = "#f8f8f2"
    c_subtext = "#8be9fd"
    c_accent_green = "#50fa7b"
    c_accent_orange = "#ffb86c"
    c_accent_pink = "#ff79c6"
    c_line = "#44475a"

    # Title
    draw.rectangle([(20, 20), (width - 20, 70)], fill="#313244", outline=c_header, width=2)
    draw.text((40, 32), "Autonomous Self-Healing Production ML Platform (Architecture)", fill=c_text)

    # Section 1: Ingress & Client
    draw.rectangle([(40, 100), (240, 260)], fill=c_card, outline=c_subtext, width=2)
    draw.text((55, 115), "Traffic & Clients", fill=c_header)
    draw.text((55, 145), "- REST API Client", fill=c_text)
    draw.text((55, 170), "- NodePort: 30080", fill=c_text)
    draw.text((55, 195), "- Locust / hey (Load)", fill=c_text)
    draw.text((55, 220), "- Synthetic Drift Tool", fill=c_accent_orange)

    # Section 2: Serving Namespace (ns: serving)
    draw.rectangle([(280, 100), (620, 380)], fill=c_card, outline=c_accent_green, width=2)
    draw.text((300, 115), "Serving Namespace (ns: serving)", fill=c_accent_green)
    draw.text((300, 145), "model-api (FastAPI, 2..6 Pods, HPA)", fill=c_text)
    draw.text((320, 175), "* Pinned Model Version (immutable)", fill=c_subtext)
    draw.text((320, 200), "* Feast Redis Online Hydration", fill=c_subtext)
    draw.text((320, 225), "* Async Prediction Logger Buffer", fill=c_subtext)
    draw.text((320, 250), "* Health / Readiness / Chaos probes", fill=c_subtext)
    draw.text((300, 285), "model-api-staging (Port 8081)", fill=c_accent_orange)
    draw.text((320, 310), "* 2,000-req load & parity gate", fill=c_subtext)
    draw.text((320, 335), "* Ephemeral validation canary", fill=c_subtext)

    # Section 3: Data Services Namespace (ns: data)
    draw.rectangle([(660, 100), (1140, 380)], fill=c_card, outline=c_header, width=2)
    draw.text((680, 115), "Data & ML Platform Namespace (ns: data)", fill=c_header)
    
    # Sub-boxes in data ns
    draw.rectangle([(680, 150), (890, 240)], fill="#383a59", outline=c_border, width=1)
    draw.text((690, 160), "Feast Online Store", fill=c_subtext)
    draw.text((690, 185), "Redis 7.2 (Port 6379)", fill=c_text)
    draw.text((690, 210), "<2ms feature hydration", fill=c_accent_green)

    draw.rectangle([(910, 150), (1120, 240)], fill="#383a59", outline=c_border, width=1)
    draw.text((920, 160), "PostgreSQL 16", fill=c_subtext)
    draw.text((920, 185), "Port 5432 (StatefulSet)", fill=c_text)
    draw.text((920, 210), "prediction_log, drift_state", fill=c_text)

    draw.rectangle([(680, 260), (890, 350)], fill="#383a59", outline=c_border, width=1)
    draw.text((690, 270), "MinIO Object Storage", fill=c_subtext)
    draw.text((690, 295), "Port 9000 (S3 Parity)", fill=c_text)
    draw.text((690, 320), "Parquet features & labels", fill=c_text)

    draw.rectangle([(910, 260), (1120, 350)], fill="#383a59", outline=c_border, width=1)
    draw.text((920, 270), "MLflow Tracking & Registry", fill=c_subtext)
    draw.text((920, 295), "Port 5000 (Artifacts in S3)", fill=c_text)
    draw.text((920, 320), "Aliases: champion / candidate", fill=c_accent_green)

    # Section 4: Closed-Loop Self-Healing & Automation (Flow C)
    draw.rectangle([(40, 420), (580, 660)], fill=c_card, outline=c_accent_orange, width=2)
    draw.text((60, 435), "Closed-Loop Model Self-Healing (Flow C)", fill=c_accent_orange)
    draw.text((60, 470), "1. drift-monitor: checks prediction_log features vs MLflow reference", fill=c_text)
    draw.text((60, 495), "2. PSI / KS breaches threshold across consecutive evaluations", fill=c_text)
    draw.text((60, 520), "3. Spawns Kubernetes Retrain Job (ns: data, ServiceAccount: retrain)", fill=c_text)
    draw.text((60, 545), "4. Retrain Job: Feast point-in-time join -> LightGBM train -> candidate", fill=c_text)
    draw.text((60, 570), "5. Quality Gate: AUC floor, regression check, schema verification", fill=c_text)
    draw.text((60, 595), "6. Staging 2,000-req load test -> Promote champion -> Rolling update", fill=c_text)
    draw.text((60, 620), "7. Drift resolves; monitor sets model_drift_detected=0", fill=c_accent_green)

    # Section 5: Observability & Infra Remediation (Flow B)
    draw.rectangle([(620, 420), (1140, 660)], fill=c_card, outline=c_accent_pink, width=2)
    draw.text((640, 435), "Observability & Infrastructure Remediation (Flow B)", fill=c_accent_pink)
    draw.text((640, 470), "Prometheus & Alertmanager (kube-prometheus-stack)", fill=c_subtext)
    draw.text((660, 495), "- Alert Rules: HighP95Latency, HighErrorRate, ModelDriftDetected", fill=c_text)
    draw.text((640, 525), "Remediator Service (FastAPI /alert webhook)", fill=c_subtext)
    draw.text((660, 550), "- Automated scaling: adjusts HPA floor minReplicas dynamically", fill=c_text)
    draw.text((660, 575), "- Correlated Grafana Annotations & audit trail", fill=c_text)
    draw.text((640, 605), "Loki + Grafana Alloy & 3 Provisioned Dashboards", fill=c_subtext)
    draw.text((660, 630), "- Service Health | Logs Explorer | ML Platform Health", fill=c_text)

    os.makedirs("docs", exist_ok=True)
    img.save("docs/architecture.png")
    print("Saved docs/architecture.png")

if __name__ == "__main__":
    create_diagram()
