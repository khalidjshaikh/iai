# ---------------------------------------------------------------------------
# Default VPC
#
# IPv6 is enabled on the existing default VPC, on one of its existing subnets,
# and on the instance. The subnet is adopted via the import block below so it
# is never recreated, and `prevent_destroy` keeps it from being deleted.
# ---------------------------------------------------------------------------

data "aws_vpc" "default" {
  default = true
}

data "aws_internet_gateway" "default" {
  filter {
    name   = "attachment.vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# The default VPC's main route table, where the IPv6 default route is added.
data "aws_route_table" "main" {
  vpc_id = data.aws_vpc.default.id

  filter {
    name   = "association.main"
    values = ["true"]
  }
}

# Request an Amazon-provided IPv6 CIDR (/56) for the default VPC.
#
# This must not be gated on the VPC's live IPv6 associations: the association
# created here is itself reported by data.aws_vpc.default, so the old
# `existing_vpc_ipv6_cidr == null` condition became false on the very next
# plan and forced Terraform to destroy/re-create the association. If the VPC
# already carries a Terraform-unmanaged IPv6 CIDR, adopt it with an `import`
# block instead of relying on a count condition here.
resource "aws_vpc_ipv6_cidr_block_association" "this" {
  count = var.enable_ipv6 ? 1 : 0

  vpc_id                           = data.aws_vpc.default.id
  assign_generated_ipv6_cidr_block = true
}

# Add the IPv6 default route (::/0) to the main route table so the instance's
# IPv6 traffic egresses through the existing internet gateway.
resource "aws_route" "ipv6_default" {
  count = var.enable_ipv6 ? 1 : 0

  route_table_id              = data.aws_route_table.main.id
  destination_ipv6_cidr_block = "::/0"
  gateway_id                  = data.aws_internet_gateway.default.id
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Subnets in the default VPC that already have an IPv6 CIDR, preferred when
# IPv6 is requested so an existing IPv6 subnet is reused when possible.
data "aws_subnets" "default_ipv6" {
  count = var.enable_ipv6 ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "ipv6-cidr-block-association.ipv6-cidr-block"
    values = ["*"]
  }
}

data "aws_subnet" "selected" {
  id = local.subnet_id
}

data "aws_ssm_parameter" "ubuntu_ami" {
  count = var.ami == "" ? 1 : 0
  name  = "/aws/service/canonical/ubuntu/server/${var.ubuntu_release}/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

# ---------------------------------------------------------------------------
# Manage the selected default subnet so it carries an IPv6 CIDR
#
# Provider v6 removed `aws_subnet_ipv6_cidr_block_association`; a subnet's
# IPv6 CIDR is now set on the `aws_subnet` resource itself. The import block
# adopts the existing default subnet rather than creating a new one.
# ---------------------------------------------------------------------------

resource "aws_subnet" "selected" {
  vpc_id            = data.aws_vpc.default.id
  cidr_block        = data.aws_subnet.selected.cidr_block
  availability_zone = data.aws_subnet.selected.availability_zone

  map_public_ip_on_launch         = data.aws_subnet.selected.map_public_ip_on_launch
  assign_ipv6_address_on_creation = false
  ipv6_cidr_block                 = local.subnet_ipv6_cidr

  lifecycle {
    # The default subnet is shared infrastructure; never let `terraform
    # destroy` delete it.
    prevent_destroy = true
  }
}

import {
  to = aws_subnet.selected
  id = local.subnet_id
}

# ---------------------------------------------------------------------------
# Locals
# ---------------------------------------------------------------------------

locals {
  # Prefer an IPv6-capable default subnet when IPv6 is requested, otherwise
  # fall back to the first default subnet.
  subnet_id = var.subnet_id != "" ? var.subnet_id : (
    var.enable_ipv6
    ? try(data.aws_subnets.default_ipv6[0].ids[0], data.aws_subnets.default.ids[0])
    : data.aws_subnets.default.ids[0]
  )

  ami_id = var.ami != "" ? var.ami : data.aws_ssm_parameter.ubuntu_ami[0].value

  # IPv6 CIDR already on the default VPC (null when absent).
  existing_vpc_ipv6_cidr = try(
    [
      for a in data.aws_vpc.default.ipv6_cidr_block_associations :
      a.ipv6_cidr_block if a.state == "associated"
    ][0],
    null
  )

  # The VPC's IPv6 CIDR: the association managed here when IPv6 is enabled,
  # otherwise any pre-existing association on the VPC.
  vpc_ipv6_cidr = try(
    aws_vpc_ipv6_cidr_block_association.this[0].ipv6_cidr_block,
    local.existing_vpc_ipv6_cidr
  )

  # Keep an existing subnet IPv6 CIDR, otherwise carve a /64 out of the VPC's
  # /56 when IPv6 is enabled.
  subnet_ipv6_cidr = (
    data.aws_subnet.selected.ipv6_cidr_block != ""
    ? data.aws_subnet.selected.ipv6_cidr_block
    : (var.enable_ipv6 && local.vpc_ipv6_cidr != null ? cidrsubnet(local.vpc_ipv6_cidr, 8, 0) : null)
  )
}

# ---------------------------------------------------------------------------
# SSH key pair
# ---------------------------------------------------------------------------

resource "aws_key_pair" "this" {
  key_name   = "${var.instance_name}-key"
  public_key = file(var.ssh_public_key_path)

  tags = merge(var.tags, { Name = "${var.instance_name}-key" })
}

# ---------------------------------------------------------------------------
# Security group: 22, 80, 443 (IPv4 + IPv6)
# ---------------------------------------------------------------------------

resource "aws_security_group" "this" {
  name        = "${var.instance_name}-sg"
  description = "Allow SSH, HTTP and HTTPS"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH (IPv4)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ingress_cidr_blocks
  }

  ingress {
    description = "HTTP (IPv4)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.ingress_cidr_blocks
  }

  ingress {
    description = "HTTPS (IPv4)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.ingress_cidr_blocks
  }

  ingress {
    description = "QUIC/UDP 443 (IPv4)"
    from_port   = 443
    to_port     = 443
    protocol    = "udp"
    cidr_blocks = var.ingress_cidr_blocks
  }

  dynamic "ingress" {
    for_each = var.enable_ipv6 ? [1] : []
    content {
      description      = "SSH (IPv6)"
      from_port        = 22
      to_port          = 22
      protocol         = "tcp"
      ipv6_cidr_blocks = var.ingress_ipv6_cidr_blocks
    }
  }

  dynamic "ingress" {
    for_each = var.enable_ipv6 ? [1] : []
    content {
      description      = "HTTP (IPv6)"
      from_port        = 80
      to_port          = 80
      protocol         = "tcp"
      ipv6_cidr_blocks = var.ingress_ipv6_cidr_blocks
    }
  }

  dynamic "ingress" {
    for_each = var.enable_ipv6 ? [1] : []
    content {
      description      = "HTTPS (IPv6)"
      from_port        = 443
      to_port          = 443
      protocol         = "tcp"
      ipv6_cidr_blocks = var.ingress_ipv6_cidr_blocks
    }
  }

  dynamic "ingress" {
    for_each = var.enable_ipv6 ? [1] : []
    content {
      description      = "QUIC/UDP 443 (IPv6)"
      from_port        = 443
      to_port          = 443
      protocol         = "udp"
      ipv6_cidr_blocks = var.ingress_ipv6_cidr_blocks
    }
  }

  egress {
    description = "All outbound IPv4"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "egress" {
    for_each = var.enable_ipv6 ? [1] : []
    content {
      description      = "All outbound IPv6"
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      ipv6_cidr_blocks = ["::/0"]
    }
  }

  tags = merge(var.tags, { Name = "${var.instance_name}-sg" })
}

# ---------------------------------------------------------------------------
# EC2 instance (in the default VPC, dual-stack)
# ---------------------------------------------------------------------------

resource "aws_instance" "this" {
  ami                         = local.ami_id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.selected.id
  associate_public_ip_address = var.associate_public_ip
  ipv6_address_count          = var.enable_ipv6 ? var.ipv6_address_count : 0
  key_name                    = aws_key_pair.this.key_name
  vpc_security_group_ids      = [aws_security_group.this.id]

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size_gb
    encrypted   = true

    tags = merge(var.tags, { Name = "${var.instance_name}-root" })
  }

  tags = merge(var.tags, { Name = var.instance_name })
}
