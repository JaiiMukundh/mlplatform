output "address" {
  description = "Hostname of the RDS instance."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "Port of the RDS instance."
  value       = aws_db_instance.this.port
}

output "endpoint" {
  description = "Connection endpoint (host:port) of the RDS instance."
  value       = aws_db_instance.this.endpoint
}
