output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.this.id
}

output "instance_arn" {
  description = "ARN of the EC2 instance"
  value       = aws_instance.this.arn
}

output "instance_public_ip" {
  description = "Public IPv4 address of the instance"
  value       = aws_instance.this.public_ip
}

output "instance_private_ip" {
  description = "Private IPv4 address of the instance"
  value       = aws_instance.this.private_ip
}

output "instance_ipv6_addresses" {
  description = "IPv6 addresses assigned to the instance"
  value       = aws_instance.this.ipv6_addresses
}

output "instance_public_dns" {
  description = "Public DNS name of the instance"
  value       = aws_instance.this.public_dns
}

output "security_group_id" {
  description = "Security group ID attached to the instance"
  value       = aws_security_group.this.id
}

output "key_pair_name" {
  description = "Name of the SSH key pair"
  value       = aws_key_pair.this.key_name
}

output "ssh_command_v4" {
  description = "SSH command using IPv4"
  value       = "ssh -i ${var.ssh_public_key_path} ubuntu@${aws_instance.this.public_ip}"
}

output "ssh_command_v6" {
  description = "SSH command using IPv6 (first assigned IPv6 address)"
  value       = length(aws_instance.this.ipv6_addresses) > 0 ? "ssh -6 -i ${var.ssh_public_key_path} ubuntu@${aws_instance.this.ipv6_addresses[0]}" : null
}
