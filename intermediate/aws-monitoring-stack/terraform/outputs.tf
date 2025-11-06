output "monitoring_server_ip" {
  description = "Public IP of the monitoring server"
  value       = aws_instance.monitoring_server.public_ip
}

output "monitored_client_ip" {
  description = "Public IP of the monitored client"
  value       = aws_instance.monitored_client.public_ip
}
