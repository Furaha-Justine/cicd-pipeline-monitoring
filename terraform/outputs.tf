output "jenkins_public_ip" {
  value = aws_instance.jenkins.public_ip
}

output "jenkins_url" {
  value = "http://${aws_instance.jenkins.public_ip}:8080"
}

output "app_public_ip" {
  value = aws_instance.app.public_ip
}

output "app_url" {
  value = "http://${aws_instance.app.public_ip}:${var.app_port}"
}

output "monitoring_public_ip" {
  value = aws_instance.monitoring.public_ip
}

output "prometheus_url" {
  value = "http://${aws_instance.monitoring.public_ip}:9090"
}

output "grafana_url" {
  value = "http://${aws_instance.monitoring.public_ip}:3001"
}

output "ssh_jenkins" {
  value = "ssh -i terraform/ec2_key.pem ec2-user@${aws_instance.jenkins.public_ip}"
}

output "ssh_app" {
  value = "ssh -i terraform/ec2_key.pem ec2-user@${aws_instance.app.public_ip}"
}

output "ssh_monitoring" {
  value = "ssh -i terraform/ec2_key.pem ec2-user@${aws_instance.monitoring.public_ip}"
}

output "cloudwatch_app_log_group" {
  value = aws_cloudwatch_log_group.app_logs.name
}

output "cloudtrail_bucket" {
  value = aws_s3_bucket.cloudtrail_logs.id
}

output "cloudtrail_name" {
  value = aws_cloudtrail.account_trail.name
}

output "guardduty_detector_id" {
  value = "managed by aws cli (see aws guardduty list-detectors)"
}
