variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "instance_name" {
  description = "Name tag for the EC2 instance"
  type        = string
  default     = "tf-ec2-vm"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "ami" {
  description = <<-EOT
    AMI ID to use. If left empty, resolves dynamically via SSM to the latest
    Ubuntu Server 26.04 LTS (Resolute Raccoon) AMI for the configured region.
  EOT
  type        = string
  default     = ""
}

variable "ubuntu_release" {
  description = "Ubuntu release version for dynamic AMI lookup (used only when var.ami is empty)"
  type        = string
  default     = "26.04"
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key to inject into the instance (absolute path, no ~)"
  type        = string
  default     = "/Users/kshaikh/.ssh/id_ed25519.pub"
}

variable "vpc_id" {
  description = "VPC ID to deploy into. Ignored when enable_ipv6 is true (creates a new VPC)."
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "Subnet ID to launch the instance into. Ignored when enable_ipv6 is true."
  type        = string
  default     = ""
}

variable "associate_public_ip" {
  description = "Whether to assign a public IP to the instance"
  type        = bool
  default     = true
}

variable "ingress_cidr_blocks" {
  description = "IPv4 CIDR blocks allowed for SSH ingress"
  type        = list(string)
  default     = ["0.0.0.0/0"]
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
    Project   = "tf-ec2-vm"
  }
}

# ---------------------------------------------------------------------------
# IPv6 options
# ---------------------------------------------------------------------------

variable "enable_ipv6" {
  description = "Enable IPv6. When true and vpc_id is empty, creates a new VPC with IPv6."
  type        = bool
  default     = true
}

variable "ipv6_address_count" {
  description = "Number of IPv6 addresses to assign to the instance"
  type        = number
  default     = 1
}

variable "ingress_ipv6_cidr_blocks" {
  description = "IPv6 CIDR blocks allowed for SSH ingress"
  type        = list(string)
  default     = ["::/0"]
}

variable "vpc_cidr" {
  description = "CIDR block for the custom VPC (used when create_vpc = true)"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the custom subnet (used when create_vpc = true)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "availability_zone" {
  description = "Availability zone for the custom subnet (used when create_vpc = true)"
  type        = string
  default     = "us-east-1a"
}
