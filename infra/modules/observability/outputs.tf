output "grafana_url" {
  description = "Host URL for Grafana (NodePort 30030 -> host 3000)."
  value       = "http://localhost:3000"
}

output "prometheus_url" {
  description = "Host URL for Prometheus (NodePort 30090 -> host 9090)."
  value       = "http://localhost:9090"
}

output "alertmanager_url" {
  description = "Host URL for Alertmanager (NodePort 30093 -> host 9093)."
  value       = "http://localhost:9093"
}
