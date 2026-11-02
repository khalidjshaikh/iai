variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "instance_name" {
  description = "Name tag for the EC2 instance"
  type        = string
  default     = "tf2-ec2-vm"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "ami" {
  description = <<-EOT
    AMI ID to use. Defaults to a pinned Ubuntu Server 26.04 LTS AMI
    (ami-09b09d2491cd88154, us-east-1) so plans are reproducible and do not
    force instance replacement when Canonical publishes a new image. Pinned
    AMIs are region-specific. Set to "" to resolve the latest via SSM instead.
  EOT
  type        = string
  default     = "ami-09b09d2491cd88154"
}

variable "ubuntu_release" {
  description = "Ubuntu release version for the dynamic AMI lookup (used only when var.ami is empty)"
  type        = string
  default     = "26.04"
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key injected into the instance (absolute path, no ~)"
  type        = string
  default     = "/Users/kshaikh/.ssh/id_ed25519.pub"
}

variable "subnet_id" {
  description = "Subnet in the default VPC to launch into. Empty = first subnet found."
  type        = string
  default     = ""
}

variable "associate_public_ip" {
  description = "Whether to associate a public IPv4 address with the instance"
  type        = bool
  default     = true
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 20
}

variable "tags" {
  description = "Additional tags applied to all resources"
  type        = map(string)
  default = {
    ManagedBy = "Terraform"
    Project   = "tf2-default-vpc-ipv6"
  }
}

# ---------------------------------------------------------------------------
# IPv6 options
# ---------------------------------------------------------------------------

variable "enable_ipv6" {
  description = "Enable IPv6 on the default VPC, the selected subnet and the instance"
  type        = bool
  default     = true
}

variable "ipv6_address_count" {
  description = "Number of IPv6 addresses to assign to the instance"
  type        = number
  default     = 1
}

# ---------------------------------------------------------------------------
# Networking / ingress
# ---------------------------------------------------------------------------

variable "ingress_cidr_blocks" {
  description = "IPv4 CIDR blocks allowed for SSH/HTTP/HTTPS ingress"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "ingress_ipv6_cidr_blocks" {
  description = "IPv6 CIDR blocks allowed for SSH/HTTP/HTTPS ingress"
  type        = list(string)
  default     = ["::/0"]
}
